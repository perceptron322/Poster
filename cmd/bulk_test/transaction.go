package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readconcern"
	"go.mongodb.org/mongo-driver/mongo/readpref"
	"go.mongodb.org/mongo-driver/mongo/writeconcern"
)

type transactionReview struct {
	EventID int32
	UserID  int32
	Rating  int32
	Text    string
}

type transactionResult struct {
	Attempts int
	Inserted bool
}

type transactionFault int

const (
	noFault transactionFault = iota
	rollbackAfterInsert
	transientOnceAfterInsert
	serverTransientOnceAfterInsert
)

var errInjectedRollback = errors.New("искусственный сбой после вставки отзыва")

// RunTransactionDemo запускает проверяемые сценарии на реальных коллекциях
// проекта. Тестовые отзывы удаляются после проверки, рейтинг восстанавливается.
func RunTransactionDemo(ctx context.Context, db *mongo.Database, scenario string) (demoErr error) {
	if scenario != "all" && scenario != "success" && scenario != "rollback" && scenario != "retry" && scenario != "server-retry" {
		return fmt.Errorf("неизвестный сценарий %q: используйте all, success, rollback, retry или server-retry", scenario)
	}

	// Используем отдельную БД, чтобы проверка не меняла содержимое poster_content.
	// Эта БД пересоздаётся при запуске и удаляется после сценариев.
	if err := db.Drop(ctx); err != nil {
		return fmt.Errorf("очистка тестовой БД: %w", err)
	}
	defer func() {
		cleanupCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := db.Drop(cleanupCtx); err != nil {
			demoErr = errors.Join(demoErr, fmt.Errorf("удаление тестовой БД: %w", err))
		}
	}()

	const fixtureEventID int32 = 900_000_001
	if _, err := db.Collection("reviews").Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys:    bson.D{{Key: "event_id", Value: 1}, {Key: "user_id", Value: 1}},
		Options: options.Index().SetName("one_review_per_user").SetUnique(true),
	}); err != nil {
		return fmt.Errorf("создание уникального индекса отзывов: %w", err)
	}
	if _, err := db.Collection("event_pages").InsertOne(ctx, bson.M{
		"_id":        fixtureEventID,
		"event":      bson.M{"type": "lecture", "status": "finished"},
		"rating":     bson.M{"count": int32(2), "avg": 4.0},
		"updated_at": time.Now(),
	}); err != nil {
		return fmt.Errorf("создание тестового мероприятия: %w", err)
	}
	if _, err := db.Collection("reviews").InsertMany(ctx, []interface{}{
		bson.M{"_id": primitive.NewObjectID(), "event_id": fixtureEventID, "user_id": int32(1), "rating": int32(5), "text": "fixture review 1", "helpful_votes": int32(0), "schemaVersion": int32(1), "created_at": time.Now()},
		bson.M{"_id": primitive.NewObjectID(), "event_id": fixtureEventID, "user_id": int32(2), "rating": int32(3), "text": "fixture review 2", "helpful_votes": int32(0), "schemaVersion": int32(1), "created_at": time.Now()},
	}); err != nil {
		return fmt.Errorf("создание исходных отзывов: %w", err)
	}

	scenarios := []string{"success", "rollback", "retry"}
	if scenario != "all" {
		scenarios = []string{scenario}
	}
	for i, name := range scenarios {
		item, err := newTransactionReview(ctx, db, fixtureEventID, int32(2_000_000_000+i), int32(5-i), "Sprint 6 transaction demo")
		if err != nil {
			return err
		}
		if err := runTransactionScenario(ctx, db, item, name); err != nil {
			return fmt.Errorf("сценарий %s: %w", name, err)
		}
	}
	return nil
}

func newTransactionReview(ctx context.Context, db *mongo.Database, eventID, startUserID, rating int32, text string) (transactionReview, error) {
	for offset := int32(0); offset < 10_000; offset++ {
		candidate := transactionReview{
			EventID: eventID,
			UserID:  startUserID + offset,
			Rating:  rating,
			Text:    text,
		}
		count, err := db.Collection("reviews").CountDocuments(ctx, bson.M{
			"event_id": candidate.EventID,
			"user_id":  candidate.UserID,
		})
		if err != nil {
			return transactionReview{}, fmt.Errorf("проверка тестового пользователя: %w", err)
		}
		if count == 0 {
			return candidate, nil
		}
	}
	return transactionReview{}, errors.New("не удалось выделить свободный тестовый user_id")
}

func runTransactionScenario(ctx context.Context, db *mongo.Database, item transactionReview, scenario string) (scenarioErr error) {
	before, err := readRating(ctx, db, item.EventID)
	if err != nil {
		return err
	}

	fault := noFault
	switch scenario {
	case "success":
	case "rollback":
		fault = rollbackAfterInsert
	case "retry":
		fault = transientOnceAfterInsert
	case "server-retry":
		fault = serverTransientOnceAfterInsert
	default:
		return fmt.Errorf("неизвестный сценарий %q", scenario)
	}

	result, txErr := writeReviewAndRefreshRating(ctx, db, item, fault)
	if scenario == "rollback" {
		if !errors.Is(txErr, errInjectedRollback) {
			return fmt.Errorf("ожидался искусственный сбой, получено: %v", txErr)
		}
		found, err := reviewExists(ctx, db, item)
		if err != nil {
			return err
		}
		after, err := readRating(ctx, db, item.EventID)
		if err != nil {
			return err
		}
		if found || after != before {
			return fmt.Errorf("откат неполный: review_exists=%t rating_before=%+v rating_after=%+v", found, before, after)
		}
		log.Printf("ROLLBACK OK: вставка отзыва и обновление rating отменены; rating=%+v", after)
		return nil
	}
	if txErr != nil {
		return txErr
	}
	if result.Inserted {
		defer func() {
			cleanupCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			if err := cleanupDemoReview(cleanupCtx, db, item); err != nil {
				scenarioErr = errors.Join(scenarioErr, fmt.Errorf("очистка тестового отзыва: %w", err))
			}
		}()
	}

	if (scenario == "retry" || scenario == "server-retry") && result.Attempts < 2 {
		return fmt.Errorf("ожидался повтор callback после временной ошибки, попыток: %d", result.Attempts)
	}
	if !result.Inserted {
		return errors.New("ожидалась новая вставка тестового отзыва")
	}
	if err := verifyReviewAndRating(ctx, db, item, before); err != nil {
		return err
	}

	// Повтор того же логического запроса должен быть идемпотентным.
	replay, err := writeReviewAndRefreshRating(ctx, db, item, noFault)
	if err != nil {
		return fmt.Errorf("идемпотентный повтор: %w", err)
	}
	if replay.Inserted {
		return errors.New("повторный запрос создал второй отзыв")
	}
	if err := verifyReviewAndRating(ctx, db, item, before); err != nil {
		return fmt.Errorf("проверка после идемпотентного повтора: %w", err)
	}
	if scenario == "retry" {
		log.Printf("RETRY OK: временная ошибка вызвала повтор callback (%d попытки), сохранился один отзыв", result.Attempts)
	} else if scenario == "server-retry" {
		log.Printf("SERVER RETRY OK: mongod вернул WriteConflict с TransientTransactionError; callback повторён %d раза", result.Attempts)
	} else {
		log.Printf("COMMIT OK: отзыв и rating зафиксированы одной транзакцией; повтор не создал дубликат")
	}

	return nil
}

func writeReviewAndRefreshRating(ctx context.Context, db *mongo.Database, item transactionReview, fault transactionFault) (transactionResult, error) {
	client := db.Client()
	session, err := client.StartSession()
	if err != nil {
		return transactionResult{}, fmt.Errorf("создание сессии: %w", err)
	}
	defer session.EndSession(ctx)

	txOptions := options.Transaction().
		SetReadConcern(readconcern.Snapshot()).
		SetWriteConcern(writeconcern.Majority()).
		SetReadPreference(readpref.Primary())
	result := transactionResult{}
	failpointArmed := false
	_, err = session.WithTransaction(ctx, func(sessionCtx mongo.SessionContext) (interface{}, error) {
		result.Attempts++
		reviews := db.Collection("reviews")
		eventPages := db.Collection("event_pages")

		var existing struct {
			Rating int32  `bson:"rating"`
			Text   string `bson:"text"`
		}
		findErr := reviews.FindOne(sessionCtx, bson.M{"event_id": item.EventID, "user_id": item.UserID}).Decode(&existing)
		if findErr == nil {
			if existing.Rating != item.Rating || existing.Text != item.Text {
				return nil, errors.New("idempotency conflict: такой event_id/user_id уже использован с другим содержимым")
			}
			result.Inserted = false
			return nil, nil
		}
		if !errors.Is(findErr, mongo.ErrNoDocuments) {
			return nil, fmt.Errorf("поиск существующего отзыва: %w", findErr)
		}

		_, err := reviews.InsertOne(sessionCtx, bson.M{
			"_id":           primitive.NewObjectID(),
			"event_id":      item.EventID,
			"user_id":       item.UserID,
			"rating":        item.Rating,
			"text":          item.Text,
			"helpful_votes": int32(0),
			"schemaVersion": int32(1),
			"created_at":    time.Now(),
		})
		if err != nil {
			return nil, fmt.Errorf("вставка отзыва: %w", err)
		}
		result.Inserted = true

		if fault == rollbackAfterInsert {
			return nil, errInjectedRollback
		}
		if fault == transientOnceAfterInsert && result.Attempts == 1 {
			return nil, mongo.CommandError{
				Code:    112,
				Message: "искусственный WriteConflict для проверки retry",
				Labels:  []string{"TransientTransactionError"},
			}
		}

		var aggregate struct {
			Count int64   `bson:"count"`
			Avg   float64 `bson:"avg"`
		}
		pipeline := mongo.Pipeline{
			{{Key: "$match", Value: bson.D{{Key: "event_id", Value: item.EventID}}}},
			{{Key: "$group", Value: bson.D{
				{Key: "_id", Value: nil},
				{Key: "count", Value: bson.D{{Key: "$sum", Value: 1}}},
				{Key: "avg", Value: bson.D{{Key: "$avg", Value: "$rating"}}},
			}}},
		}
		cursor, err := reviews.Aggregate(sessionCtx, pipeline)
		if err != nil {
			return nil, fmt.Errorf("агрегация рейтинга: %w", err)
		}
		defer cursor.Close(sessionCtx)
		if !cursor.Next(sessionCtx) {
			if err := cursor.Err(); err != nil {
				return nil, fmt.Errorf("чтение агрегата рейтинга: %w", err)
			}
			return nil, errors.New("после вставки отзыва агрегат пуст")
		}
		if err := cursor.Decode(&aggregate); err != nil {
			return nil, fmt.Errorf("декодирование агрегата рейтинга: %w", err)
		}
		if fault == serverTransientOnceAfterInsert && result.Attempts == 1 {
			if err := configureTransientWriteFailpoint(ctx, client); err != nil {
				return nil, fmt.Errorf("настройка серверного failpoint: %w", err)
			}
			failpointArmed = true
		}

		update, err := eventPages.UpdateOne(sessionCtx, bson.M{"_id": item.EventID}, bson.M{
			"$set": bson.M{
				"rating.count": int32(aggregate.Count),
				"rating.avg":   math.Round(aggregate.Avg*100) / 100,
				"updated_at":   time.Now(),
			},
		})
		if err != nil {
			return nil, fmt.Errorf("обновление кэша rating: %w", err)
		}
		if update.MatchedCount != 1 {
			return nil, fmt.Errorf("event_pages _id=%d не найден", item.EventID)
		}
		return nil, nil
	}, txOptions)
	var failpointErr error
	if failpointArmed {
		if err == nil {
			failpointErr = waitForTransientWriteFailpoint(ctx, client)
		}
		disableCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if disableErr := disableTransientWriteFailpoint(disableCtx, client); disableErr != nil {
			failpointErr = errors.Join(failpointErr, disableErr)
		}
	}
	if err != nil {
		return result, err
	}
	if failpointErr != nil {
		return result, failpointErr
	}
	return result, nil
}

func configureTransientWriteFailpoint(ctx context.Context, client *mongo.Client) error {
	var response struct {
		Count int64 `bson:"count"`
	}
	command := bson.D{
		{Key: "configureFailPoint", Value: "failCommand"},
		{Key: "mode", Value: bson.D{{Key: "times", Value: 1}}},
		{Key: "data", Value: bson.D{
			{Key: "failCommands", Value: bson.A{"update"}},
			{Key: "errorCode", Value: 112},
			{Key: "errorLabels", Value: bson.A{"TransientTransactionError"}},
			{Key: "appName", Value: "poster-tx-failpoint-test"},
		}},
	}
	if err := client.Database("admin").RunCommand(ctx, command).Decode(&response); err != nil {
		return fmt.Errorf("configureFailPoint: %w", err)
	}
	return nil
}

func waitForTransientWriteFailpoint(ctx context.Context, client *mongo.Client) error {
	command := bson.D{
		{Key: "waitForFailPoint", Value: "failCommand"},
		{Key: "timesEntered", Value: 1},
		{Key: "maxTimeMS", Value: 5000},
	}
	if err := client.Database("admin").RunCommand(ctx, command).Err(); err != nil {
		return fmt.Errorf("failCommand не был активирован: %w", err)
	}
	return nil
}

func disableTransientWriteFailpoint(ctx context.Context, client *mongo.Client) error {
	command := bson.D{
		{Key: "configureFailPoint", Value: "failCommand"},
		{Key: "mode", Value: "off"},
	}
	if err := client.Database("admin").RunCommand(ctx, command).Err(); err != nil {
		return fmt.Errorf("отключение failCommand: %w", err)
	}
	return nil
}

type ratingSnapshot struct {
	Count int32
	Avg   float64
}

func readRating(ctx context.Context, db *mongo.Database, eventID int32) (ratingSnapshot, error) {
	var page struct {
		Rating struct {
			Count int32   `bson:"count"`
			Avg   float64 `bson:"avg"`
		} `bson:"rating"`
	}
	err := db.Collection("event_pages").FindOne(ctx, bson.M{"_id": eventID}).Decode(&page)
	if err != nil {
		return ratingSnapshot{}, fmt.Errorf("чтение rating: %w", err)
	}
	return ratingSnapshot{Count: page.Rating.Count, Avg: page.Rating.Avg}, nil
}

func reviewExists(ctx context.Context, db *mongo.Database, item transactionReview) (bool, error) {
	count, err := db.Collection("reviews").CountDocuments(ctx, bson.M{"event_id": item.EventID, "user_id": item.UserID})
	return count != 0, err
}

func verifyReviewAndRating(ctx context.Context, db *mongo.Database, item transactionReview, before ratingSnapshot) error {
	var review struct {
		ID primitive.ObjectID `bson:"_id"`
	}
	if err := db.Collection("reviews").FindOne(ctx, bson.M{"event_id": item.EventID, "user_id": item.UserID}).Decode(&review); err != nil {
		return fmt.Errorf("проверка сохранённого отзыва: %w", err)
	}
	after, err := readRating(ctx, db, item.EventID)
	if err != nil {
		return err
	}
	aggregate, err := aggregateRating(ctx, db, item.EventID)
	if err != nil {
		return err
	}
	if after.Count != aggregate.Count || math.Abs(after.Avg-aggregate.Avg) > 0.01 {
		return fmt.Errorf("кэш рейтинга расходится с reviews: cache=%+v aggregate=%+v", after, aggregate)
	}
	if after.Count != before.Count+1 {
		return fmt.Errorf("ожидалось увеличение count на 1: было %+v, стало %+v", before, after)
	}
	return nil
}

func aggregateRating(ctx context.Context, db *mongo.Database, eventID int32) (ratingSnapshot, error) {
	pipeline := mongo.Pipeline{
		{{Key: "$match", Value: bson.D{{Key: "event_id", Value: eventID}}}},
		{{Key: "$group", Value: bson.D{
			{Key: "_id", Value: nil},
			{Key: "count", Value: bson.D{{Key: "$sum", Value: 1}}},
			{Key: "avg", Value: bson.D{{Key: "$avg", Value: "$rating"}}},
		}}},
	}
	cursor, err := db.Collection("reviews").Aggregate(ctx, pipeline)
	if err != nil {
		return ratingSnapshot{}, fmt.Errorf("агрегация reviews: %w", err)
	}
	defer cursor.Close(ctx)
	var aggregate struct {
		Count int64   `bson:"count"`
		Avg   float64 `bson:"avg"`
	}
	if !cursor.Next(ctx) {
		if err := cursor.Err(); err != nil {
			return ratingSnapshot{}, fmt.Errorf("чтение агрегата reviews: %w", err)
		}
		return ratingSnapshot{}, errors.New("агрегация reviews не вернула результат")
	}
	if err := cursor.Decode(&aggregate); err != nil {
		return ratingSnapshot{}, fmt.Errorf("декодирование агрегата reviews: %w", err)
	}
	return ratingSnapshot{Count: int32(aggregate.Count), Avg: aggregate.Avg}, nil
}

func cleanupDemoReview(ctx context.Context, db *mongo.Database, item transactionReview) error {
	if _, err := db.Collection("reviews").DeleteOne(ctx, bson.M{"event_id": item.EventID, "user_id": item.UserID}); err != nil {
		return fmt.Errorf("удаление тестового отзыва: %w", err)
	}
	aggregate, err := aggregateRating(ctx, db, item.EventID)
	if err != nil {
		return err
	}
	result, err := db.Collection("event_pages").UpdateOne(ctx, bson.M{"_id": item.EventID}, bson.M{
		"$set": bson.M{
			"rating.count": aggregate.Count,
			"rating.avg":   math.Round(aggregate.Avg*100) / 100,
			"updated_at":   time.Now(),
		},
	})
	if err != nil {
		return err
	}
	if result.MatchedCount != 1 {
		return fmt.Errorf("event_pages _id=%d не найден при восстановлении rating", item.EventID)
	}
	return nil
}
