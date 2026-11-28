package api

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"slices"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

var mongoUnavailable = &problem{503, "unavailable", "MongoDB недоступна"}

func contentError(err error) error {
	var serverErr mongo.ServerError
	switch {
	case err == nil:
		return nil
	case errors.Is(err, mongo.ErrNoDocuments):
		return missing
	case mongo.IsTimeout(err), mongo.IsNetworkError(err):
		return mongoUnavailable
	case errors.As(err, &serverErr):
		if serverErr.HasErrorCode(121) {
			return invalid("Содержимое страницы не соответствует типу мероприятия или схеме MongoDB")
		}
		if serverErr.HasErrorCode(13) || serverErr.HasErrorCode(18) {
			return mongoUnavailable
		}
	}
	return err
}

type snapshot struct {
	Title  string    `json:"title" bson:"title"`
	Type   string    `json:"type" bson:"type"`
	Status string    `json:"status" bson:"status"`
	Starts time.Time `json:"starts_at" bson:"starts_at"`
	Ends   time.Time `json:"ends_at" bson:"ends_at"`
	owner  int
}

// The public page and permission checks use PostgreSQL even if the imported snapshot is old.
func currentSnapshot(ctx context.Context, db reader, id int, lockClause string) (snapshot, error) {
	query := "SELECT title,type,status,datetime,datetime+duration,user_id FROM events WHERE event_id=$1"

	var e snapshot
	err := db.QueryRowContext(ctx, query+lockClause, id).Scan(&e.Title, &e.Type, &e.Status, &e.Starts, &e.Ends, &e.owner)
	return e, err
}

type stage struct {
	Name  string `json:"name" bson:"name"`
	Genre string `json:"genre" bson:"genre"`
}
type pageDetails struct {
	Genre     *string  `json:"genre,omitempty" bson:"genre,omitempty"`
	Age       *int32   `json:"age_limit,omitempty" bson:"age_limit,omitempty"`
	Setlist   *bool    `json:"setlist_public,omitempty" bson:"setlist_public,omitempty"`
	Topic     *string  `json:"topic,omitempty" bson:"topic,omitempty"`
	Level     *string  `json:"level,omitempty" bson:"level,omitempty"`
	Materials []string `json:"materials,omitempty" bson:"materials,omitempty"`
	Troupe    *string  `json:"troupe_id,omitempty" bson:"troupe_id,omitempty"`
	Acts      *int32   `json:"acts,omitempty" bson:"acts,omitempty"`
	Stages    []stage  `json:"stages,omitempty" bson:"stages,omitempty"`
	Note      *string  `json:"note,omitempty" bson:"note,omitempty"`
}
type programItem struct {
	Starts    time.Time `json:"starts_at" bson:"starts_at"`
	Title     string    `json:"title" bson:"title"`
	Performer string    `json:"performer_id,omitempty" bson:"performer_id,omitempty"`
	Stage     string    `json:"stage,omitempty" bson:"stage,omitempty"`
}
type pageInput struct {
	Summary    string        `json:"summary"`
	Details    *pageDetails  `json:"details"`
	Program    []programItem `json:"program"`
	Performers []string      `json:"performer_ids"`
	Gallery    []string      `json:"gallery"`
}
type eventContent struct {
	ID         int           `bson:"_id" json:"event_id"`
	Event      snapshot      `bson:"event" json:"event"`
	Summary    string        `bson:"summary" json:"summary"`
	Details    pageDetails   `bson:"details" json:"details"`
	Program    []programItem `bson:"program" json:"program"`
	Performers []string      `bson:"performer_ids" json:"performer_ids"`
	Gallery    []string      `bson:"gallery" json:"gallery"`
	Rating     rating        `bson:"rating" json:"rating"`
	Version    *int          `bson:"schemaVersion" json:"-"`
	Content    struct {
		Summary string `bson:"summary"`
	} `bson:"content" json:"-"`
}
type performer struct {
	ID     string   `bson:"_id" json:"id"`
	Name   string   `bson:"name" json:"name"`
	Kind   string   `bson:"kind" json:"kind"`
	Bio    string   `bson:"bio" json:"bio,omitempty"`
	Genres []string `bson:"genres" json:"genres,omitempty"`
	Links  *struct {
		Site    string   `bson:"site" json:"site,omitempty"`
		Socials []string `bson:"socials" json:"socials,omitempty"`
	} `bson:"links" json:"links,omitempty"`
	Photo   string `bson:"photo" json:"photo,omitempty"`
	Version *int   `bson:"schemaVersion" json:"-"`
}

func (s *server) performers(r request) (any, error) {
	limit, offset, err := pagination(r)
	if err != nil {
		return nil, err
	}
	cursor, err := s.content.Collection("performers").Find(r.Context(), bson.M{}, options.Find().SetSort(bson.D{{Key: "_id", Value: 1}}).SetLimit(int64(limit)).SetSkip(int64(offset)))
	if err != nil {
		return nil, contentError(err)
	}
	rows := []performer{}
	if err := cursor.All(r.Context(), &rows); err != nil {
		return nil, contentError(err)
	}
	for _, p := range rows {
		if p.Version != nil && *p.Version != 1 {
			return nil, errors.New("unsupported performer version")
		}
	}
	return rows, nil
}

func (s *server) readPage(ctx context.Context, id int, e snapshot) (eventContent, error) {
	var p eventContent
	err := s.content.Collection("event_pages").FindOne(ctx, bson.M{"_id": id, "event.type": e.Type}).Decode(&p)
	if err != nil {
		return p, contentError(err)
	}
	if p.Version != nil {
		switch *p.Version {
		case 1: // legacy summary is already decoded
		case 2:
			p.Summary = p.Content.Summary
		default:
			return p, errors.New("unsupported event page version")
		}
	}
	p.Event = e
	if p.Gallery == nil {
		p.Gallery = []string{}
	}
	// A failed cache update after inserting a review must not affect public ratings.
	p.Rating, err = s.reviewRating(ctx, id)
	return p, err
}

func (s *server) eventPage(r request) (any, error) {
	e, err := currentSnapshot(r.Context(), s.db, r.id, "")
	if err != nil {
		return nil, err
	}
	if e.Status == "cancelled" {
		return nil, missing
	}
	return s.readPage(r.Context(), r.id, e)
}

func (s *server) validatePage(ctx context.Context, e snapshot, in pageInput) error {
	if in.Details == nil || in.Program == nil || in.Performers == nil || len(in.Performers) > 30 || len(in.Program) > 50 || len(in.Gallery) > 20 {
		return invalid("Проверьте обязательные поля и размер списков страницы")
	}
	for _, part := range in.Program {
		if part.Starts.IsZero() || (part.Performer != "" && !slices.Contains(in.Performers, part.Performer)) {
			return invalid("Проверьте время и исполнителя в программе")
		}
		if e.Type == "festival" && !slices.ContainsFunc(in.Details.Stages, func(s stage) bool { return part.Stage == s.Name }) {
			return invalid("Сцена программы отсутствует в списке сцен фестиваля")
		}
	}
	if len(in.Performers) > 0 {
		n, err := s.content.Collection("performers").CountDocuments(ctx, bson.M{"_id": bson.M{"$in": in.Performers}})
		if err != nil {
			return contentError(err)
		}
		if int(n) != len(in.Performers) {
			return invalid("Укажите существующих исполнителей без повторов")
		}
	}
	if e.Type == "theatre" && in.Details.Troupe != nil {
		err := s.content.Collection("performers").FindOne(ctx, bson.M{"_id": *in.Details.Troupe, "kind": "troupe"}).Err()
		if errors.Is(err, mongo.ErrNoDocuments) {
			return invalid("Труппа не найдена")
		}
		if err != nil {
			return contentError(err)
		}
	}
	return nil
}

func (s *server) savePage(r request) (any, error) {
	var in pageInput
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	ctx := r.Context()
	return transaction(ctx, s.db, func(tx *sql.Tx) (eventContent, error) {
		e, err := currentSnapshot(ctx, tx, r.id, " FOR UPDATE")
		if err != nil {
			return eventContent{}, err
		}
		if e.owner != r.user.ID {
			return eventContent{}, forbidden
		}
		if e.Status != "published" || !e.Starts.After(time.Now()) {
			return eventContent{}, conflict("Публикация контента закрыта")
		}
		if err := s.validatePage(ctx, e, in); err != nil {
			return eventContent{}, err
		}
		now := time.Now().UTC()
		if in.Gallery == nil {
			in.Gallery = []string{}
		}
		content := bson.M{}
		if in.Summary != "" {
			content["summary"] = in.Summary
		}
		update := bson.M{"$set": bson.M{"schemaVersion": int32(2), "event": e, "content": content, "details": in.Details,
			"program": in.Program, "performer_ids": in.Performers, "gallery": in.Gallery, "updated_at": now, "synced_at": now},
			"$unset": bson.M{"summary": ""}, "$setOnInsert": bson.M{"rating": rating{}}}
		_, err = s.content.Collection("event_pages").UpdateOne(ctx, bson.M{"_id": int32(r.id), "schemaVersion": bson.M{"$in": bson.A{nil, 1, 2}}}, update, options.UpdateOne().SetUpsert(true))
		if mongo.IsDuplicateKeyError(err) {
			return eventContent{}, conflict("Неподдерживаемая версия страницы")
		}
		if err != nil {
			return eventContent{}, contentError(err)
		}
		return s.readPage(ctx, r.id, e)
	})
}

// Refresh an existing compatible snapshot after a committed change in PostgreSQL.
// Holding a shared lock while reading the latest event prevents older updates overtaking newer ones.
func (s *server) syncSnapshot(ctx context.Context, id int) {
	_, err := transaction(ctx, s.db, func(tx *sql.Tx) (struct{}, error) {
		e, err := currentSnapshot(ctx, tx, id, " FOR SHARE")
		if err != nil {
			return struct{}{}, err
		}
		_, err = s.content.Collection("event_pages").UpdateOne(ctx, bson.M{"_id": id, "event.type": e.Type},
			bson.M{"$set": bson.M{"event": e, "synced_at": time.Now().UTC()}})
		return struct{}{}, err
	})
	if err != nil {
		log.Printf("Не удалось обновить снимок мероприятия %d в MongoDB", id)
	}
}
