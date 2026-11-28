package api

import (
	"context"
	"fmt"
	"time"
)

type location struct {
	ID       int    `json:"id"`
	Name     string `json:"name"`
	Address  string `json:"address"`
	Capacity int    `json:"capacity"`
}

type event struct {
	ID            int       `json:"id"`
	Title         string    `json:"title"`
	Description   string    `json:"description"`
	Cover         string    `json:"cover"`
	StartsAt      time.Time `json:"starts_at"`
	Duration      float64   `json:"duration_minutes"`
	Type          string    `json:"type"`
	Price         string    `json:"ticket_price"`
	Status        string    `json:"status"`
	OrganizerID   int       `json:"organizer_id"`
	OrganizerName string    `json:"organizer_name"`
	Location      location  `json:"location"`
	Available     int       `json:"available"`
}

const occupiedSeats = `(SELECT count(*) FROM orders o JOIN tickets t USING(order_id)
	WHERE o.event_id=e.event_id AND t.status IN ('valid','used'))`

const eventSelect = `SELECT e.event_id,e.title,coalesce(e.description,''),coalesce(e.cover,''),e.datetime,
	extract(epoch FROM e.duration)/60,e.type,e.ticket_price,e.status,u.user_id,u.name,
	l.location_id,l.name,l.address,l.capacity,
	CASE WHEN e.status='published' AND e.datetime>now() THEN greatest(0,l.capacity-` + occupiedSeats + `) ELSE 0 END
	FROM events e JOIN users u USING(user_id) JOIN locations l USING(location_id) `

const upcoming = "e.status='published' AND e.datetime>now()"

func scanEvent(row scanner) (event, error) {
	var e event
	err := row.Scan(&e.ID, &e.Title, &e.Description, &e.Cover, &e.StartsAt, &e.Duration, &e.Type, &e.Price, &e.Status,
		&e.OrganizerID, &e.OrganizerName, &e.Location.ID, &e.Location.Name, &e.Location.Address, &e.Location.Capacity, &e.Available)
	return e, err
}

func getEvent(ctx context.Context, db reader, id int) (event, error) {
	return scanEvent(db.QueryRowContext(ctx, eventSelect+" WHERE e.event_id=$1", id))
}

func (s *server) publicEvent(r request) (any, error) {
	return scanEvent(s.db.QueryRowContext(r.Context(), eventSelect+" WHERE e.event_id=$1 AND "+upcoming, r.id))
}

func (s *server) catalog(r request) (any, error) {
	from, to, err := period(r)
	if err != nil {
		return nil, err
	}
	q := r.URL.Query()
	kind := q.Get("type")
	if kind != "" && !eventType(kind) {
		return nil, invalid("Неизвестный тип мероприятия")
	}
	// Bind only supplied filters, so PostgreSQL can use the date index for a calendar range.
	where := upcoming
	args := []any{}
	add := func(expr string, value any) {
		args = append(args, value)
		where += " AND " + fmt.Sprintf(expr, len(args))
	}
	if name := q.Get("q"); name != "" {
		add("strpos(lower(e.title),lower($%d))>0", name)
	}
	if kind != "" {
		add("e.type=$%d", kind)
	}
	if from != nil {
		add("e.datetime >= $%d", *from)
	}
	if to != nil {
		add("e.datetime < $%d", *to)
	}
	return s.listEvents(r, where, args)
}

func (s *server) myEvents(r request) (any, error) {
	return s.listEvents(r, "e.user_id=$1", []any{r.user.ID})
}

func (s *server) listEvents(r request, where string, args []any) (any, error) {
	limit, offset, err := pagination(r)
	if err != nil {
		return nil, err
	}
	sql := eventSelect + " WHERE " + where + fmt.Sprintf(" ORDER BY e.datetime,e.event_id LIMIT $%d OFFSET $%d", len(args)+1, len(args)+2)
	rows, err := s.db.QueryContext(r.Context(), sql, append(args, limit, offset)...)
	if err != nil {
		return nil, err
	}
	return collect(rows, scanEvent)
}

func (s *server) locations(r request) (any, error) {
	limit, offset, err := pagination(r)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.QueryContext(r.Context(), "SELECT location_id,name,address,capacity FROM locations ORDER BY location_id LIMIT $1 OFFSET $2", limit, offset)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(row scanner) (location, error) {
		var l location
		err := row.Scan(&l.ID, &l.Name, &l.Address, &l.Capacity)
		return l, err
	})
}

type booking struct {
	EventID int       `json:"event_id"`
	Start   time.Time `json:"start"`
	End     time.Time `json:"end"`
}

func (s *server) bookings(r request) (any, error) {
	limit, offset, err := pagination(r)
	if err != nil {
		return nil, err
	}
	from, to, err := period(r)
	if err != nil {
		return nil, err
	}
	var exists bool
	if err := s.db.QueryRowContext(r.Context(), "SELECT EXISTS(SELECT FROM locations WHERE location_id=$1)", r.id).Scan(&exists); err != nil {
		return nil, err
	}
	if !exists {
		return nil, missing
	}
	rows, err := s.db.QueryContext(r.Context(), `SELECT event_id,start_time,end_time FROM location_bookings
		WHERE location_id=$1 AND end_time>coalesce($2::timestamptz,now()) AND ($3::timestamptz IS NULL OR start_time<$3)
		ORDER BY start_time,event_id LIMIT $4 OFFSET $5`, r.id, from, to, limit, offset)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(row scanner) (booking, error) {
		var b booking
		err := row.Scan(&b.EventID, &b.Start, &b.End)
		return b, err
	})
}
