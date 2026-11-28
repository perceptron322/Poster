package api

import (
	"context"
	"database/sql"
	"errors"
	"time"
	"unicode/utf8"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

type rating struct {
	Count   int32    `bson:"count" json:"count"`
	Average *float64 `bson:"avg" json:"avg"`
}
type review struct {
	ID      bson.ObjectID `bson:"_id" json:"id"`
	EventID int32         `bson:"event_id" json:"event_id"`
	UserID  int32         `bson:"user_id" json:"user_id"`
	Rating  int32         `bson:"rating" json:"rating"`
	Text    string        `bson:"text,omitempty" json:"text,omitempty"`
	Created time.Time     `bson:"created_at" json:"created_at"`
	Version *int32        `bson:"schemaVersion" json:"-"`
}

func (s *server) reviewRating(ctx context.Context, id int) (rating, error) {
	cursor, err := s.content.Collection("reviews").Aggregate(ctx, bson.A{
		bson.M{"$match": bson.M{"event_id": id}},
		bson.M{"$group": bson.M{"_id": nil, "count": bson.M{"$sum": 1}, "avg": bson.M{"$avg": "$rating"}}},
		bson.M{"$project": bson.M{"count": 1, "avg": bson.M{"$round": bson.A{"$avg", 2}}}},
	})
	if err != nil {
		return rating{}, contentError(err)
	}
	defer cursor.Close(ctx)
	var result rating
	if cursor.Next(ctx) {
		err = cursor.Decode(&result)
	} else {
		err = cursor.Err()
	}
	return result, contentError(err)
}

func (s *server) reviews(r request) (any, error) {
	limit, offset, err := pagination(r)
	if err != nil {
		return nil, err
	}
	ctx := r.Context()
	e, err := currentSnapshot(ctx, s.db, r.id, "")
	if err != nil {
		return nil, err
	}
	if e.Status == "cancelled" {
		return nil, missing
	}
	cursor, err := s.content.Collection("reviews").Find(ctx, bson.M{"event_id": r.id}, options.Find().SetLimit(int64(limit)).SetSkip(int64(offset)).
		SetSort(bson.D{{Key: "created_at", Value: -1}, {Key: "_id", Value: -1}}))
	if err != nil {
		return nil, contentError(err)
	}
	items := []review{}
	if err := cursor.All(ctx, &items); err != nil {
		return nil, contentError(err)
	}
	for _, v := range items {
		if v.Version != nil && *v.Version != 1 {
			return nil, errors.New("unsupported review version")
		}
	}
	return items, nil
}

func (s *server) addReview(r request) (any, error) {
	var in struct {
		Rating int32  `json:"rating"`
		Text   string `json:"text"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if in.Rating < 1 || in.Rating > 5 || utf8.RuneCountInString(in.Text) > 4000 {
		return nil, invalid("Оценка должна быть от 1 до 5, текст — до 4000 символов")
	}
	ctx := r.Context()
	// Complete an elapsed published event before writing any review to MongoDB.
	// Existing finished events (including imports) are already eligible.
	_, err := s.db.ExecContext(ctx, `UPDATE events e SET status='finished'
		WHERE event_id=$1 AND status='published' AND datetime+duration<=clock_timestamp()
		AND EXISTS(SELECT FROM orders WHERE event_id=e.event_id AND user_id=$2 AND status='paid')`, r.id, r.user.ID)
	if err != nil {
		return nil, err
	}
	return transaction(ctx, s.db, func(tx *sql.Tx) (review, error) {
		// Serialize rating cache updates with other API reviews of this event.
		e, err := currentSnapshot(ctx, tx, r.id, " FOR UPDATE")
		if err != nil {
			return review{}, err
		}
		if e.Status == "cancelled" {
			return review{}, missing
		}
		if e.Status != "finished" {
			return review{}, conflict("Отзывы принимаются после завершения мероприятия")
		}
		var paid bool
		err = tx.QueryRowContext(ctx, "SELECT EXISTS(SELECT FROM orders WHERE event_id=$1 AND user_id=$2 AND status='paid')", r.id, r.user.ID).Scan(&paid)
		if err != nil {
			return review{}, err
		}
		if !paid {
			return review{}, forbidden
		}
		pages := s.content.Collection("event_pages")
		if err = pages.FindOne(ctx, bson.M{"_id": r.id, "event.type": e.Type, "schemaVersion": bson.M{"$in": bson.A{nil, 1, 2}}}).Err(); err != nil {
			return review{}, contentError(err)
		}
		version := int32(1)
		item := review{ID: bson.NewObjectID(), EventID: int32(r.id), UserID: int32(r.user.ID), Rating: in.Rating, Text: in.Text, Created: time.Now().UTC().Truncate(time.Millisecond), Version: &version}
		_, err = s.content.Collection("reviews").InsertOne(ctx, item)
		duplicate := mongo.IsDuplicateKeyError(err)
		if err != nil && !duplicate {
			return review{}, contentError(err)
		}
		// Recompute even for a retry after a disconnected client or a failed cache write.
		score, err := s.reviewRating(ctx, r.id)
		if err != nil {
			return review{}, err
		}
		_, err = pages.UpdateByID(ctx, r.id, bson.M{"$set": bson.M{"rating": score, "event": e, "synced_at": time.Now().UTC()}})
		if err != nil {
			return review{}, contentError(err)
		}
		if duplicate {
			return review{}, conflict("Вы уже оставили отзыв")
		}
		return item, nil
	})
}
