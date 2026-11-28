package api

import (
	"context"
	"database/sql"
	"math"
	"net/url"
	"regexp"
	"strings"
	"time"
)

type eventInput struct {
	Title       *string    `json:"title"`
	Description *string    `json:"description"`
	Cover       *string    `json:"cover"`
	StartsAt    *time.Time `json:"starts_at"`
	Duration    *int32     `json:"duration_minutes"`
	Type        *string    `json:"type"`
	Price       *string    `json:"ticket_price"`
	LocationID  *int       `json:"location_id"`
}

func eventType(s string) bool {
	switch s {
	case "concert", "lecture", "theatre", "festival", "other":
		return true
	}
	return false
}

var money = regexp.MustCompile(`^(0|[1-9][0-9]{0,7})(\.[0-9]{1,2})?$`)

func (e eventInput) validate(create bool) error {
	if create && (e.Title == nil || e.Description == nil || e.Cover == nil || e.StartsAt == nil || e.Duration == nil || e.Type == nil || e.Price == nil || e.LocationID == nil) {
		return invalid("Заполните все поля мероприятия")
	}
	if e.Title != nil && !validText(*e.Title, 300) {
		return invalid("Проверьте название мероприятия")
	}
	if e.Description != nil && strings.TrimSpace(*e.Description) == "" {
		return invalid("Введите описание")
	}
	if e.Cover != nil {
		u, err := url.Parse(*e.Cover)
		if err != nil || u.Hostname() == "" || (u.Scheme != "http" && u.Scheme != "https") || !validText(*e.Cover, 500) {
			return invalid("Укажите HTTP(S) URL обложки")
		}
	}
	if e.StartsAt != nil && !e.StartsAt.After(time.Now()) {
		return invalid("Начало должно быть в будущем")
	}
	if e.Duration != nil && *e.Duration < 1 {
		return invalid("Длительность должна быть положительной")
	}
	if e.Type != nil && !eventType(*e.Type) {
		return invalid("Неизвестный тип мероприятия")
	}
	if e.Price != nil && (!money.MatchString(*e.Price) || strings.Trim(*e.Price, "0.") == "") {
		return invalid("Укажите положительную цену с точностью до копеек")
	}
	if e.LocationID != nil && (*e.LocationID < 1 || *e.LocationID > math.MaxInt32) {
		return invalid("Некорректная площадка")
	}
	return nil
}

func reserve(ctx context.Context, tx *sql.Tx, id int) error {
	result, err := tx.ExecContext(ctx, `INSERT INTO location_bookings(event_id,location_id,start_time,end_time)
		SELECT event_id,location_id,datetime,datetime+duration FROM events
		WHERE event_id=$1 AND datetime>clock_timestamp()
		AND datetime+duration < timestamptz '10000-01-01 00:00:00+00'`, id)
	if err != nil {
		return err
	}
	count, err := result.RowsAffected()
	if err == nil && count == 0 {
		return invalid("Проверьте дату начала и окончания мероприятия")
	}
	return err
}

func (s *server) createEvent(r request) (any, error) {
	var e eventInput
	if err := decode(r, &e); err != nil {
		return nil, err
	}
	if err := e.validate(true); err != nil {
		return nil, err
	}
	return transaction(r.Context(), s.db, func(tx *sql.Tx) (event, error) {
		var id int
		err := tx.QueryRowContext(r.Context(), `INSERT INTO events(title,description,cover,datetime,duration,type,ticket_price,location_id,user_id)
			VALUES($1,$2,$3,$4,$5::integer*interval '1 minute',$6,$7,$8,$9) RETURNING event_id`,
			e.Title, e.Description, e.Cover, e.StartsAt, e.Duration, e.Type, e.Price, e.LocationID, r.user.ID).Scan(&id)
		if err != nil {
			return event{}, err
		}
		if err := reserve(r.Context(), tx, id); err != nil {
			return event{}, err
		}
		return getEvent(r.Context(), tx, id)
	})
}

// Every writer of an event, its orders or tickets takes the event lock first.
// In READ COMMITTED the next statement then sees the preceding writer's commit.
type lockedEvent struct {
	owner  int
	starts time.Time
	status string
}

func lockEvent(ctx context.Context, tx *sql.Tx, id int) (lockedEvent, error) {
	var e lockedEvent
	err := tx.QueryRowContext(ctx, "SELECT user_id,datetime,status FROM events WHERE event_id=$1 FOR UPDATE", id).Scan(&e.owner, &e.starts, &e.status)
	return e, err
}

func (e lockedEvent) active() error {
	if e.status != "published" || !e.starts.After(time.Now()) {
		return conflict("Мероприятие отменено или уже началось")
	}
	return nil
}

func lockOwned(r request, tx *sql.Tx) error {
	e, err := lockEvent(r.Context(), tx, r.id)
	if err != nil {
		return err
	}
	if e.owner != r.user.ID {
		return forbidden
	}
	return e.active()
}

func (s *server) editEvent(r request) (any, error) {
	var e eventInput
	if err := decode(r, &e); err != nil {
		return nil, err
	}
	if err := e.validate(false); err != nil {
		return nil, err
	}
	return transaction(r.Context(), s.db, func(tx *sql.Tx) (event, error) {
		ctx := r.Context()
		if err := lockOwned(r, tx); err != nil {
			return event{}, err
		}
		move := e.StartsAt != nil || e.Duration != nil || e.LocationID != nil
		if move || e.Title != nil || e.Type != nil || e.Price != nil {
			var sold bool
			if err := tx.QueryRowContext(ctx, "SELECT EXISTS(SELECT FROM orders WHERE event_id=$1)", r.id).Scan(&sold); err != nil {
				return event{}, err
			}
			if sold {
				return event{}, conflict("После первой продажи можно менять только описание и обложку")
			}
		}
		if move {
			if _, err := tx.ExecContext(ctx, "DELETE FROM location_bookings WHERE event_id=$1", r.id); err != nil {
				return event{}, err
			}
		}
		_, err := tx.ExecContext(ctx, `UPDATE events SET title=coalesce($2,title),description=coalesce($3,description),
			cover=coalesce($4,cover),datetime=coalesce($5,datetime),duration=coalesce($6::integer*interval '1 minute',duration),
			type=coalesce($7,type),ticket_price=coalesce($8,ticket_price),location_id=coalesce($9,location_id)
			WHERE event_id=$1`, r.id, e.Title, e.Description, e.Cover, e.StartsAt, e.Duration, e.Type, e.Price, e.LocationID)
		if err != nil {
			return event{}, err
		}
		if move {
			if err := reserve(ctx, tx, r.id); err != nil {
				return event{}, err
			}
		}
		return getEvent(ctx, tx, r.id)
	})
}

func (s *server) cancelEvent(r request) (any, error) {
	return transaction(r.Context(), s.db, func(tx *sql.Tx) (event, error) {
		if err := lockOwned(r, tx); err != nil {
			return event{}, err
		}
		for _, stmt := range []string{
			"UPDATE events SET status='cancelled' WHERE event_id=$1",
			`UPDATE tickets t SET status='cancelled' FROM orders o WHERE t.order_id=o.order_id AND o.event_id=$1 AND t.status='valid'`,
			"UPDATE orders SET status='cancelled',total_price=0 WHERE event_id=$1 AND status IN ('paid','pending')",
			"DELETE FROM location_bookings WHERE event_id=$1",
		} {
			if _, err := tx.ExecContext(r.Context(), stmt, r.id); err != nil {
				return event{}, err
			}
		}
		return getEvent(r.Context(), tx, r.id)
	})
}
