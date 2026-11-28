package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"log"
	"mime"
	"net/http"
	"reflect"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/lib/pq"

	"github.com/perceptron322/poster/docs"
)

type server struct {
	db           *sql.DB
	secureCookie bool
}

type request struct {
	*http.Request
	writer http.ResponseWriter
	user   user
	id     int
}

type handler func(request) (any, error)

func New(db *sql.DB, secureCookie bool) http.Handler {
	s := server{db, secureCookie}
	mux := http.NewServeMux()
	docs.Register(mux)
	route := func(pattern, role string, status int, fn handler) {
		mux.HandleFunc(pattern, func(w http.ResponseWriter, req *http.Request) {
			r := request{Request: req, writer: w}
			w.Header().Set("Cache-Control", "no-store")
			if role != "" {
				u, err := s.currentUser(r)
				if err != nil {
					writeError(w, err)
					return
				}
				if role == "organizer" && u.Role != role {
					writeError(w, forbidden)
					return
				}
				r.user = u
			}
			if raw := req.PathValue("id"); raw != "" {
				var err error
				r.id, err = positiveID(raw)
				if err != nil {
					writeError(w, err)
					return
				}
			}
			value, err := fn(r)
			if err != nil {
				writeError(w, err)
				return
			}
			if status == http.StatusNoContent {
				w.WriteHeader(status)
				return
			}
			writeJSON(w, status, value)
		})
	}
	route("GET /readyz", "", 200, s.ready)
	const base = "/api/v1"
	route("POST "+base+"/auth/register", "", 201, s.register)
	route("POST "+base+"/auth/login", "", 200, s.login)
	route("POST "+base+"/auth/logout", "user", 204, s.logout)
	route("GET "+base+"/me", "user", 200, func(r request) (any, error) { return r.user, nil })
	route("GET "+base+"/locations", "", 200, s.locations)
	route("GET "+base+"/locations/{id}/bookings", "", 200, s.bookings)
	route("GET "+base+"/events", "", 200, s.catalog)
	route("GET "+base+"/events/{id}", "", 200, s.publicEvent)
	route("GET "+base+"/me/events", "organizer", 200, s.myEvents)
	route("POST "+base+"/events", "organizer", 201, s.createEvent)
	route("PATCH "+base+"/events/{id}", "organizer", 200, s.editEvent)
	route("POST "+base+"/events/{id}/cancel", "organizer", 200, s.cancelEvent)
	route("POST "+base+"/orders", "user", 201, s.purchase)
	route("GET "+base+"/me/orders", "user", 200, s.orders)
	route("GET "+base+"/me/orders/{id}", "user", 200, s.myOrder)
	route("POST "+base+"/me/orders/{id}/refunds", "user", 200, s.refund)
	protection := http.NewCrossOriginProtection()
	protection.SetDenyHandler(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { writeError(w, forbidden) }))
	return protection.Handler(mux)
}

type problem struct {
	status  int
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *problem) Error() string { return e.Message }
func invalid(msg string) error   { return &problem{400, "invalid_request", msg} }
func conflict(msg string) error  { return &problem{409, "conflict", msg} }

var (
	unauthorized = &problem{401, "unauthorized", "Требуется вход в систему"}
	forbidden    = &problem{403, "forbidden", "Недостаточно прав"}
	missing      = &problem{404, "not_found", "Объект не найден"}
)

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("Ответ HTTP: %v", err)
	}
}

func writeError(w http.ResponseWriter, err error) {
	var p *problem
	var pg *pq.Error
	switch {
	case errors.As(err, &p):
	case errors.Is(err, sql.ErrNoRows):
		p = missing
	case errors.As(err, &pg):
		switch pg.Code {
		case "23P01":
			p = &problem{409, "booking_conflict", "Площадка занята в выбранное время"}
		case "23505":
			p = &problem{409, "conflict", "Запись уже существует"}
		case "23503":
			p = &problem{400, "invalid_reference", "Связанный объект не существует"}
		case "22021", "22008", "22003", "23514", "22001":
			p = &problem{400, "invalid_request", "Недопустимое значение поля"}
		}
	}
	if p == nil {
		// SQL diagnostics can contain request data. Log the type and SQLSTATE only.
		if pg != nil {
			log.Printf("Ошибка БД: SQLSTATE %s", pg.Code)
		} else {
			log.Printf("Внутренняя ошибка: %T", err)
		}
		p = &problem{500, "internal_error", "Внутренняя ошибка сервера"}
	}
	writeJSON(w, p.status, p)
}

func decode(r request, dst any) error {
	media, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || media != "application/json" {
		return &problem{415, "unsupported_media_type", "Требуется application/json"}
	}
	body, err := io.ReadAll(http.MaxBytesReader(r.writer, r.Body, 1<<20))
	if err != nil {
		var limit *http.MaxBytesError
		if errors.As(err, &limit) {
			return &problem{413, "body_too_large", "Слишком большой запрос"}
		}
		return invalid("Ошибка чтения запроса")
	}
	var fields map[string]json.RawMessage
	if !utf8.Valid(body) || json.Unmarshal(body, &fields) != nil || len(fields) == 0 {
		return invalid("Ожидается непустой объект JSON")
	}
	// encoding/json also accepts case-insensitive matches. The contract uses
	// exact field names so a misspelled field cannot silently change a request.
	typ := reflect.TypeOf(dst).Elem()
	for i := 0; i < typ.NumField(); i++ {
		key := typ.Field(i).Tag.Get("json")
		if string(fields[key]) == "null" {
			return invalid("Поля не могут быть null")
		}
		delete(fields, key)
	}
	if len(fields) != 0 {
		return invalid("Неизвестное поле")
	}
	if err := json.Unmarshal(body, dst); err != nil {
		return invalid("Неизвестное поле или неверный тип значения")
	}
	return nil
}

func positiveID(raw string) (int, error) {
	n, err := strconv.ParseInt(raw, 10, 32)
	if err != nil || n < 1 {
		return 0, invalid("Некорректный идентификатор")
	}
	return int(n), nil
}

func validText(v string, max int) bool {
	return strings.TrimSpace(v) != "" && !strings.ContainsRune(v, 0) && utf8.RuneCountInString(v) <= max
}

func pagination(r request) (int, int, error) {
	q := r.URL.Query()
	limit, offset := int64(20), int64(0)
	var err error
	if q.Has("limit") {
		limit, err = strconv.ParseInt(q.Get("limit"), 10, 32)
		if err != nil || limit < 1 || limit > 100 {
			return 0, 0, invalid("limit должен быть от 1 до 100")
		}
	}
	if q.Has("offset") {
		offset, err = strconv.ParseInt(q.Get("offset"), 10, 32)
		if err != nil || offset < 0 {
			return 0, 0, invalid("offset должен быть неотрицательным")
		}
	}
	return int(limit), int(offset), nil
}

func period(r request) (*time.Time, *time.Time, error) {
	q := r.URL.Query()
	parse := func(key string) (*time.Time, error) {
		if !q.Has(key) {
			return nil, nil
		}
		t, err := time.Parse(time.RFC3339Nano, q.Get(key))
		if err != nil {
			return nil, invalid("Для " + key + " требуется дата и время RFC 3339")
		}
		return &t, nil
	}
	from, err := parse("from")
	if err != nil {
		return nil, nil, err
	}
	to, err := parse("to")
	if err != nil {
		return nil, nil, err
	}
	if from != nil && to != nil && !from.Before(*to) {
		return nil, nil, invalid("from должно предшествовать to")
	}
	return from, to, nil
}

func (s *server) ready(r request) (any, error) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.db.PingContext(ctx); err != nil {
		return nil, &problem{503, "unavailable", "PostgreSQL недоступен"}
	}
	return map[string]string{"status": "ok"}, nil
}

type reader interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}
type scanner interface{ Scan(...any) error }

func transaction[T any](ctx context.Context, db *sql.DB, fn func(*sql.Tx) (T, error)) (T, error) {
	var zero T
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return zero, err
	}
	defer tx.Rollback()
	v, err := fn(tx)
	if err != nil {
		return zero, err
	}
	if err := tx.Commit(); err != nil {
		return zero, err
	}
	return v, nil
}

func collect[T any](rows *sql.Rows, read func(scanner) (T, error)) ([]T, error) {
	defer rows.Close()
	items := make([]T, 0)
	for rows.Next() {
		v, err := read(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, v)
	}
	return items, rows.Err()
}
