package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readconcern"
	"go.mongodb.org/mongo-driver/mongo/readpref"
	"go.mongodb.org/mongo-driver/mongo/writeconcern"
)

type ReviewBatchItem struct {
	EventID int
	UserID  int
	Rating  int
	Text    string
}

func ProcessReviewsBatch(ctx context.Context, db *mongo.Database, items []ReviewBatchItem) error {
	reviewsColl := db.Collection("reviews")
	eventPagesColl := db.Collection("event_pages")

	var reviewModels []mongo.WriteModel
	for _, item := range items {
		reviewModels = append(reviewModels, mongo.NewInsertOneModel().SetDocument(bson.M{
			"event_id":      item.EventID,
			"user_id":       item.UserID,
			"rating":        item.Rating,
			"text":          item.Text,
			"helpful_votes": 0,
			"schemaVersion": 1,
			"created_at":    time.Now(),
		}))
	}

	opts := options.BulkWrite().SetOrdered(false)
	resReviews, err := reviewsColl.BulkWrite(ctx, reviewModels, opts)

	failedInsertIndices := make(map[int]bool)
	var batchErr error

	if err != nil {
		if bulkErr, ok := err.(mongo.BulkWriteException); ok {
			log.Printf("⚠️ Проход 1: Частичные ошибки при вставке отзывов.")
			for _, writeErr := range bulkErr.WriteErrors {
				failedInsertIndices[writeErr.Index] = true
				log.Printf("  ❌ Ошибка в операции #%d (код: %d): %s", writeErr.Index, writeErr.Code, writeErr.Message)
			}
			batchErr = fmt.Errorf("частичный сбой вставки: %w", err)
		} else {
			return fmt.Errorf("критическая ошибка при вставке отзывов: %w", err)
		}
	} else {
		log.Printf("✅ Проход 1: Успешно вставлено %d отзывов", resReviews.InsertedCount)
	}

	var eventModels []mongo.WriteModel
	for i, item := range items {

		if failedInsertIndices[i] {
			continue
		}

		eventModels = append(eventModels, mongo.NewUpdateOneModel().
			SetFilter(bson.M{"_id": item.EventID}).
			SetUpdate(bson.M{
				"$inc": bson.M{"rating.count": 1},
				"$set": bson.M{"updated_at": time.Now()},
			}).
			SetUpsert(false))
	}

	if len(eventModels) > 0 {
		resEvents, err := eventPagesColl.BulkWrite(ctx, eventModels, opts)
		if err != nil {

			if bulkErr, ok := err.(mongo.BulkWriteException); ok {
				log.Printf("⚠️ Проход 2: Частичные ошибки при обновлении мероприятий.")
				for _, writeErr := range bulkErr.WriteErrors {
					log.Printf("  ❌ Ошибка обновления #%d (код: %d): %s", writeErr.Index, writeErr.Code, writeErr.Message)
				}
			} else {
				log.Printf("🔥 Критическая ошибка при обновлении мероприятий: %v", err)
			}
		} else {
			log.Printf("✅ Проход 2: Успешно обновлено счётчиков: %d", resEvents.ModifiedCount)
		}
	}

	return batchErr
}

func main() {
	mode := flag.String("mode", "bulk", "Режим: bulk или transaction")
	scenario := flag.String("scenario", "all", "Сценарий транзакции: all, success, rollback или retry")
	flag.Parse()

	timeout := 10 * time.Second
	if *mode == "transaction" {
		timeout = 2 * time.Minute
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {

		mongoURI = "mongodb://poster:<password>@localhost:27018/poster_content?authSource=admin"
		log.Println("⚠️ Предупреждение: MONGO_URI не задан, используется заглушка. Подключение может не пройти.")
	}

	clientOptions := options.Client().ApplyURI(mongoURI)
	if *mode == "transaction" {
		clientOptions.SetReadConcern(readconcern.Majority())
		clientOptions.SetWriteConcern(writeconcern.Majority())
		clientOptions.SetReadPreference(readpref.Primary())
		if *scenario == "server-retry" {
			clientOptions.SetAppName("poster-tx-failpoint-test")
		}
	} else if *mode != "bulk" {
		log.Fatalf("Неизвестный режим %q: используйте bulk или transaction", *mode)
	}
	client, err := mongo.Connect(ctx, clientOptions)
	if err != nil {
		log.Fatalf("Ошибка подключения к MongoDB: %v", err)
	}
	defer client.Disconnect(ctx)

	if err := client.Ping(ctx, nil); err != nil {
		log.Fatalf("Не удалось пингануть MongoDB: %v", err)
	}
	log.Println("✅ Успешное подключение к MongoDB")

	databaseName := "poster_content"
	if *mode == "transaction" {
		databaseName = "poster_tx_demo"
	}
	db := client.Database(databaseName)
	if *mode == "transaction" {
		if err := RunTransactionDemo(ctx, db, *scenario); err != nil {
			log.Fatalf("Сценарий транзакции завершился ошибкой: %v", err)
		}
		return
	}

	batch := []ReviewBatchItem{
		{EventID: 1, UserID: 101, Rating: 5, Text: "Отличное мероприятие!"},
		{EventID: 1, UserID: 102, Rating: 4, Text: "Понравилось"},
		{EventID: 1, UserID: 103, Rating: 10, Text: "Нарушение валидации схемы"},
		{EventID: 2, UserID: 104, Rating: 5, Text: "Супер"},
	}

	log.Println("🚀 Запуск двухпроходной пакетной обработки...")
	err = ProcessReviewsBatch(ctx, db, batch)

	if err != nil {
		log.Printf("⚠️ Процесс завершился с ошибками: %v", err)
	} else {
		log.Println("🎉 Процесс завершился идеально!")
	}
}
