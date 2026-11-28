package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"math"
	"regexp"
	"time"

	"github.com/lib/pq"
)

type ticket struct {
	ID     int    `json:"id"`
	Price  string `json:"price"`
	Status string `json:"status"`
}
type order struct {
	ID         int       `json:"id"`
	EventID    int       `json:"event_id"`
	EventTitle string    `json:"event_title"`
	CreatedAt  time.Time `json:"created_at"`
	Status     string    `json:"status"`
	Total      string    `json:"total_price"`
	Tickets    []ticket  `json:"tickets"`
}

const orderSelect = `SELECT o.order_id,o.event_id,e.title,o.created_at,o.status,o.total_price,
	coalesce((SELECT json_agg(json_build_object('id',t.ticket_id,'status',t.status,'price',t.price::text) ORDER BY t.ticket_id)
		FROM tickets t WHERE t.order_id=o.order_id),'[]'::json)
	FROM orders o JOIN events e USING(event_id) WHERE o.user_id=$1 `

func scanOrder(row scanner) (order, error) {
	var o order
	var tickets []byte
	err := row.Scan(&o.ID, &o.EventID, &o.EventTitle, &o.CreatedAt, &o.Status, &o.Total, &tickets)
	if err == nil {
		err = json.Unmarshal(tickets, &o.Tickets)
	}
	return o, err
}
func getOrder(ctx context.Context, db reader, userID, id int) (order, error) {
	return scanOrder(db.QueryRowContext(ctx, orderSelect+" AND o.order_id=$2", userID, id))
}
func (s *server) myOrder(r request) (any, error) {
	return getOrder(r.Context(), s.db, r.user.ID, r.id)
}
func (s *server) orders(r request) (any, error) {
	limit, offset, err := pagination(r)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.QueryContext(r.Context(), orderSelect+" AND o.status<>'refunded' ORDER BY o.created_at DESC,o.order_id DESC LIMIT $2 OFFSET $3", r.user.ID, limit, offset)
	if err != nil {
		return nil, err
	}
	return collect(rows, scanOrder)
}

var purchaseKey = regexp.MustCompile(`^[A-Za-z0-9._-]{1,128}$`)

func (s *server) purchase(r request) (any, error) {
	if r.user.Role != "organizer" && r.user.Role != "customer" {
		return nil, forbidden
	}
	var in struct {
		EventID  int `json:"event_id"`
		Quantity int `json:"quantity"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if in.EventID <= 0 || in.EventID > math.MaxInt32 || in.Quantity < 1 || in.Quantity > 5 {
		return nil, invalid("Укажите мероприятие и от 1 до 5 билетов")
	}
	key := r.Header.Get("Idempotency-Key")
	if key != "" && !purchaseKey.MatchString(key) {
		return nil, invalid("Некорректный Idempotency-Key")
	}
	ctx := r.Context()
	return transaction(ctx, s.db, func(tx *sql.Tx) (order, error) {
		e, err := lockEvent(ctx, tx, in.EventID)
		if err != nil {
			return order{}, err
		}
		if key != "" {
			prior, err := scanOrder(tx.QueryRowContext(ctx, orderSelect+" AND o.purchase_key=$2", r.user.ID, key))
			if err == nil {
				if prior.EventID != in.EventID || len(prior.Tickets) != in.Quantity {
					return order{}, conflict("Ключ уже использован для другого запроса")
				}
				return prior, nil
			}
			if !errors.Is(err, sql.ErrNoRows) {
				return order{}, err
			}
		}
		if err := e.active(); err != nil {
			return order{}, err
		}
		var id int
		// A separate SQL statement after acquiring the lock sees current sales.
		err = tx.QueryRowContext(ctx, `INSERT INTO orders(event_id,user_id,status,total_price,purchase_key)
			SELECT e.event_id,$2,'paid',e.ticket_price*$3::integer,nullif($4,'')
			FROM events e JOIN locations l USING(location_id) WHERE e.event_id=$1
			AND e.datetime>clock_timestamp() AND l.capacity-`+occupiedSeats+` >= $3 RETURNING order_id`,
			in.EventID, r.user.ID, in.Quantity, key).Scan(&id)
		if errors.Is(err, sql.ErrNoRows) {
			return order{}, conflict("Продажа закрыта или недостаточно мест")
		}
		if err != nil {
			return order{}, err
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO tickets(order_id,price,status)
			SELECT $1,e.ticket_price,'valid' FROM events e CROSS JOIN generate_series(1,$2::integer)
			WHERE e.event_id=$3`, id, in.Quantity, in.EventID)
		if err != nil {
			return order{}, err
		}
		return getOrder(ctx, tx, r.user.ID, id)
	})
}

func (s *server) refund(r request) (any, error) {
	var in struct {
		IDs []int64 `json:"ticket_ids"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if len(in.IDs) == 0 {
		return nil, invalid("Выберите билеты для возврата")
	}
	seen := map[int64]bool{}
	for _, id := range in.IDs {
		if id < 1 || id > math.MaxInt32 || seen[id] {
			return nil, invalid("Ожидаются уникальные идентификаторы билетов")
		}
		seen[id] = true
	}
	ctx := r.Context()
	return transaction(ctx, s.db, func(tx *sql.Tx) (order, error) {
		var eventID int
		err := tx.QueryRowContext(ctx, "SELECT event_id FROM orders WHERE order_id=$1 AND user_id=$2", r.id, r.user.ID).Scan(&eventID)
		if err != nil {
			return order{}, err
		}
		e, err := lockEvent(ctx, tx, eventID)
		if err != nil {
			return order{}, err
		}
		if err := e.active(); err != nil {
			return order{}, err
		}
		result, err := tx.ExecContext(ctx, `UPDATE tickets t SET status='returned' FROM orders o
			WHERE t.order_id=o.order_id AND o.order_id=$1 AND o.status='paid'
			AND t.status='valid' AND t.ticket_id=ANY($2::int[])`, r.id, pq.Array(in.IDs))
		if err != nil {
			return order{}, err
		}
		n, err := result.RowsAffected()
		if err != nil {
			return order{}, err
		}
		if int(n) != len(in.IDs) {
			return order{}, conflict("Все выбранные билеты должны быть активными и принадлежать заказу")
		}
		_, err = tx.ExecContext(ctx, `UPDATE orders SET total_price=t.total,
			status=CASE WHEN t.all_returned THEN 'refunded' ELSE status END
			FROM (SELECT coalesce(sum(price) FILTER (WHERE status='valid'),0) AS total,
				bool_and(status='returned') AS all_returned FROM tickets WHERE order_id=$1) t
			WHERE order_id=$1`, r.id)
		if err != nil {
			return order{}, err
		}
		return getOrder(ctx, tx, r.user.ID, r.id)
	})
}
