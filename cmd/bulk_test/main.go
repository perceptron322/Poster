package main

import (
	"context"
	"log"
	"os"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
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
	var eventModels []mongo.WriteModel

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

		eventModels = append(eventModels, mongo.NewUpdateOneModel().
			SetFilter(bson.M{"_id": item.EventID}).
			SetUpdate(bson.M{
				"$inc": bson.M{"rating.count": 1},
				"$set": bson.M{"updated_at": time.Now()},
			}).
			SetUpsert(false))
	}

	opts := options.BulkWrite().SetOrdered(false)

	resReviews, err := reviewsColl.BulkWrite(ctx, reviewModels, opts)
	if err != nil {
		handleBulkError(err, resReviews, "отзывы")
	} else {
		log.Printf("✅ Отзывы: успешно вставлено %d", resReviews.InsertedCount)
	}

	resEvents, err := eventPagesColl.BulkWrite(ctx, eventModels, opts)
	if err != nil {
		handleBulkError(err, resEvents, "мероприятия")
	} else {
		log.Printf("✅ Мероприятия: успешно обновлено %d", resEvents.ModifiedCount)
	}

	return nil
}

func handleBulkError(err error, result *mongo.BulkWriteResult, entityName string) {
	if bulkErr, ok := err.(mongo.BulkWriteException); ok {
		log.Printf("⚠️ Пакетная обработка '%s' завершена с частичными ошибками. Успешно: %d",
			entityName, result.InsertedCount+result.ModifiedCount)

		for _, writeErr := range bulkErr.WriteErrors {
			log.Printf("  ❌ Ошибка в операции #%d (код: %d): %s", writeErr.Index, writeErr.Code, writeErr.Message)
			if writeErr.Code == 121 {
				log.Printf("     -> Документ пропущен: нарушение JSON Schema валидации.")
			} else if writeErr.Code == 11000 {
				log.Printf("     -> Документ пропущен: дубликат уникального ключа.")
			}
		}
	} else {
		log.Printf("🔥 Критическая ошибка при обработке '%s': %v", entityName, err)
	}
}

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		log.Fatal("Переменная окружения MONGO_URI не задана")
	}

	clientOptions := options.Client().ApplyURI(mongoURI)
	client, err := mongo.Connect(ctx, clientOptions)
	if err != nil {
		log.Fatalf("Ошибка подключения к MongoDB: %v", err)
	}
	defer client.Disconnect(ctx)

	if err := client.Ping(ctx, nil); err != nil {
		log.Fatalf("Не удалось пингануть MongoDB: %v", err)
	}
	log.Println("✅ Успешное подключение к MongoDB")

	db := client.Database("poster_content")

	batch := []ReviewBatchItem{
		{EventID: 1, UserID: 101, Rating: 5, Text: "Отличное мероприятие!"},
		{EventID: 1, UserID: 102, Rating: 4, Text: "Понравилось"},
		{EventID: 1, UserID: 103, Rating: 10, Text: "Этот отзыв нарушит валидацию схемы, если она настроена"},
		{EventID: 2, UserID: 104, Rating: 5, Text: "Супер"},
	}

	log.Println("🚀 Запуск пакетной обработки...")
	err = ProcessReviewsBatch(ctx, db, batch)
	if err != nil {
		log.Printf("Процесс завершился с предупреждениями: %v", err)
	} else {
		log.Println("🎉 Процесс завершился идеально!")
	}
}
