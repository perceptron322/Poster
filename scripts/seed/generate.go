package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math" // [З3-логнормаль] добавлено для Exp/NormFloat64/Pow
	"math/rand"
	"os"
	"time"

	_ "github.com/lib/pq"
)

type Config struct {
	Seed       int64  `json:"seed"`
	Mode       string `json:"mode"`
	Dsn        string `json:"dsn"`
	TicketRows int    `json:"ticket_rows"`
}

func loadConfig(path string) Config {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	var c Config
	if err := json.Unmarshal(b, &c); err != nil {
		log.Fatalf("parse: %v", err)
	}
	if c.Seed == 0 {
		c.Seed = 42
	}
	if c.Dsn == "" {
		c.Dsn = "postgres://poster:secret@localhost:5433/poster?sslmode=disable"
	}
	switch c.Mode {
	case "", "dev":
		c.Mode = "dev"
		if c.TicketRows == 0 {
			c.TicketRows = 75_000
		}
	case "load":
		if c.TicketRows == 0 {
			c.TicketRows = 3_500_000
		}
	default:
		log.Fatalf("mode must be dev|load, got %q", c.Mode)
	}
	return c
}

// rngFor — детерминированный PRNG на таблицу/колонку.
// Один и тот же seed + теги всегда дают одну последовательность.
func rngFor(seed int64, tags ...string) *rand.Rand {
	h := int64(1469598103934665603)
	mix := func(s string) {
		for _, b := range []byte(s) {
			h ^= int64(b)
			h *= 1099511628211
		}
	}
	mix(fmt.Sprint(seed))
	for _, t := range tags {
		mix(":")
		mix(t)
	}
	return rand.New(rand.NewSource(h))
}

// ---------- [З3-веса] Справочники с весами ----------
//
// Веса задают неравномерность: популярные значения встречаются чаще.
// pick() выбирает значение пропорционально весам.

var (
	roleVals    = []string{"guest", "customer", "organizer"}
	roleWeights = []float64{5, 80, 15}

	eventTypes = []string{"concert", "lecture", "theatre", "festival", "other"}
	eventTypeW = []float64{35, 25, 20, 10, 10}

	eventStatus  = []string{"published", "cancelled", "finished"}
	eventStatusW = []float64{70, 5, 25}

	orderStatus  = []string{"pending", "paid", "cancelled", "refunded"}
	orderStatusW = []float64{5, 80, 10, 5}

	ticketStatus  = []string{"valid", "used", "returned", "cancelled"}
	ticketStatusW = []float64{70, 20, 7, 3}
)

// pick возвращает значение из vals с вероятностью, пропорциональной weights.
func pick(r *rand.Rand, vals []string, weights []float64) string {
	total := 0.0
	for _, w := range weights {
		total += w
	}
	x := r.Float64() * total
	acc := 0.0
	for i, w := range weights {
		acc += w
		if x <= acc {
			return vals[i]
		}
	}
	return vals[len(vals)-1]
}

// zipfIndex — [З3-Zipf] аппроксимация Zipf: маленькие индексы чаще.
// s — параметр распределения; s=1.2 даёт «80% на 20%».
func zipfIndex(r *rand.Rand, n int, s float64) int {
	u := r.Float64()
	x := math.Pow(u, -1.0/s) - 1.0
	if x < 0 {
		x = 0
	}
	i := int(x * float64(n) / 10.0)
	if i >= n {
		i = n - 1
	}
	return i
}

// ---------- метаданные события ----------

type eventRow struct {
	ID         int64
	UserID     int64
	LocationID int64
	Datetime   time.Time
	Duration   time.Duration
	Price      float64
	Status     string // [З3-скип] нужен, чтобы не бронировать и не покупать cancelled
}

// ---------- main ----------

func main() {
	var cfgPath string
	flag.StringVar(&cfgPath, "config", "config.json", "path to config.json")
	flag.Parse()

	cfg := loadConfig(cfgPath)
	log.Printf("mode=%s seed=%d target_tickets=%d", cfg.Mode, cfg.Seed, cfg.TicketRows)

	db, err := sql.Open("postgres", cfg.Dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	tx, err := db.Begin()
	if err != nil {
		log.Fatal(err)
	}
	defer tx.Rollback()

	userIDs := genUsers(tx, cfg)
	log.Printf("users: %d", len(userIDs))

	locIDs := genLocations(tx, cfg)
	log.Printf("locations: %d", len(locIDs))

	rows := genEventsWithMeta(tx, cfg, userIDs, locIDs)
	log.Printf("events: %d", len(rows))

	genBookings(tx, cfg, rows)
	log.Printf("bookings done")

	genOrdersAndTickets(tx, cfg, userIDs, rows)

	if err := tx.Commit(); err != nil {
		log.Fatal(err)
	}
	log.Printf("mode=%s seed=%d done", cfg.Mode, cfg.Seed)
}

// ---------- users ----------

func genUsers(tx *sql.Tx, cfg Config) []int64 {
	r := rngFor(cfg.Seed, "users")
	n := 1_000
	if cfg.Mode == "load" {
		n = 50_000
	}

	stmt, err := tx.Prepare(`INSERT INTO users (name, email, role)
	                         VALUES ($1,$2,$3) RETURNING user_id`)
	if err != nil {
		log.Fatal(err)
	}
	defer stmt.Close()

	ids := make([]int64, 0, n)
	for i := 0; i < n; i++ {
		var id int64
		name := fmt.Sprintf("user_%d", i)
		email := fmt.Sprintf("u%d_%d@example.com", cfg.Seed, i)
		// [З3-веса] было равномерное r.Intn(3), стало pick по весам
		role := pick(r, roleVals, roleWeights)
		if err := stmt.QueryRow(name, email, role).Scan(&id); err != nil {
			log.Fatalf("insert user: %v", err)
		}
		ids = append(ids, id)
	}
	return ids
}

// ---------- locations ----------

func genLocations(tx *sql.Tx, cfg Config) []int64 {
	r := rngFor(cfg.Seed, "locations")
	n := 20
	cities := []string{"Moscow", "SPb", "Novosibirsk", "Kazan", "Sochi"}

	stmt, err := tx.Prepare(`INSERT INTO locations (name, address, capacity)
	                         VALUES ($1,$2,$3) RETURNING location_id`)
	if err != nil {
		log.Fatal(err)
	}
	defer stmt.Close()

	ids := make([]int64, 0, n)
	for i := 0; i < n; i++ {
		var id int64
		// [З3-логнормаль] было cap := 50 + r.Intn(950) — равномерно.
		// Стало: логнормаль — много маленьких залов, мало огромных.
		capacity := int(math.Round(math.Exp(r.NormFloat64()*0.8 + 4.5)))
		if capacity < 10 {
			capacity = 10
		}
		city := cities[r.Intn(len(cities))]
		name := fmt.Sprintf("Venue %d", i)
		addr := fmt.Sprintf("%s, street %d", city, i)
		if err := stmt.QueryRow(name, addr, capacity).Scan(&id); err != nil {
			log.Fatalf("insert location: %v", err)
		}
		ids = append(ids, id)
	}
	return ids
}

// ---------- events ----------

func genEventsWithMeta(tx *sql.Tx, cfg Config, userIDs, locIDs []int64) []eventRow {
	r := rngFor(cfg.Seed, "events")
	n := 500
	if cfg.Mode == "load" {
		n = 20_000
	}
	// [З3-веса] types остаётся для справки, но выбор — через pick(eventTypes, eventTypeW)
	types := []string{"concert", "lecture", "theatre", "festival", "other"}
	_ = types

	stmt, err := tx.Prepare(`
		INSERT INTO events
		  (title, description, cover, datetime, duration, type,
		   ticket_price, status, user_id, location_id)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
		RETURNING event_id`)
	if err != nil {
		log.Fatal(err)
	}
	defer stmt.Close()

	now := time.Now().UTC()
	windowStart := now.AddDate(0, 0, -30)
	windowSecs := int64(60 * 24 * 3600) // [З3-сгущение] 60 дней в секундах

	rows := make([]eventRow, 0, n)
	for i := 0; i < n; i++ {
		// [З3-сгущение] Было равномерное r.Int63n(windowSecs).
		// Стало: Pow(u, 2) — 50-й процентиль u → 25-й процентиль frac.
		// События сгущаются к началу окна (плотное прошлое, редкое будущее).
		frac := math.Pow(r.Float64(), 2.0)
		start := windowStart.Add(
			time.Duration(frac*float64(windowSecs)) * time.Second,
		)

		durMin := 60 + r.Intn(120)
		dur := time.Duration(durMin) * time.Minute
		durStr := fmt.Sprintf("%d minutes", durMin)

		// [З3-статус] Прошедшее → finished, будущее → published|cancelled по весам.
		status := "published"
		if start.Before(now) {
			status = "finished"
		} else {
			status = pick(r, eventStatus[:2], eventStatusW[:2])
		}

		// [З3-логнормаль] Было price := float64(500 + r.Intn(4500)).
		// Стало: логнормаль — много дешёвых билетов, мало дорогих.
		price := math.Round(math.Exp(r.NormFloat64()*0.7+6.0)*100) / 100
		if price < 100 {
			price = 100
		}

		org := userIDs[r.Intn(len(userIDs))]
		loc := locIDs[r.Intn(len(locIDs))]

		var id int64
		err := stmt.QueryRow(
			fmt.Sprintf("Event %d", i),
			"description "+fmt.Sprint(i),
			fmt.Sprintf("http://img/%d.jpg", i),
			start, durStr,
			// [З3-веса] было types[r.Intn(len(types))], стало pick
			pick(r, eventTypes, eventTypeW),
			price, status, org, loc,
		).Scan(&id)
		if err != nil {
			log.Fatalf("insert event: %v", err)
		}

		rows = append(rows, eventRow{
			ID:         id,
			UserID:     org,
			LocationID: loc,
			Datetime:   start,
			Duration:   dur,
			Price:      price,
			Status:     status, // [З3-скип] сохраняем для genBookings/genOrdersAndTickets
		})
	}
	return rows
}

// ---------- location_bookings ----------

func genBookings(tx *sql.Tx, cfg Config, events []eventRow) {
	stmt, err := tx.Prepare(`
		INSERT INTO location_bookings (location_id, event_id, start_time, end_time)
		VALUES ($1,$2,$3,$4)`)
	if err != nil {
		log.Fatal(err)
	}
	defer stmt.Close()

	for _, e := range events {
		// [З3-скип] Отменённое событие площадку не занимает.
		if e.Status == "cancelled" {
			continue
		}
		if _, err := stmt.Exec(e.LocationID, e.ID, e.Datetime, e.Datetime.Add(e.Duration)); err != nil {
			log.Fatalf("insert booking: %v", err)
		}
	}
}

// ---------- orders + tickets ----------

func genOrdersAndTickets(tx *sql.Tx, cfg Config, userIDs []int64, events []eventRow) {
	r := rngFor(cfg.Seed, "orders")

	avgTickets := 2.5
	targetOrders := int(float64(cfg.TicketRows) / avgTickets)

	ordStmt, err := tx.Prepare(`
		INSERT INTO orders (created_at, status, total_price, user_id, event_id)
		VALUES ($1,$2,$3,$4,$5) RETURNING order_id`)
	if err != nil {
		log.Fatal(err)
	}
	defer ordStmt.Close()

	tkStmt, err := tx.Prepare(`
		INSERT INTO tickets (price, status, order_id)
		VALUES ($1,$2,$3)`)
	if err != nil {
		log.Fatal(err)
	}
	defer tkStmt.Close()

	ordersTotal, ticketsTotal := 0, 0

	for i := 0; i < targetOrders; i++ {
		// [З3-Zipf] Было ev := events[r.Intn(len(events))] — равномерно.
		// Стало: 80% заказов на «топовые» события, 20% — равномерно по остальным.
		var ev eventRow
		if r.Float64() < 0.8 {
			ev = events[zipfIndex(r, len(events), 1.2)]
		} else {
			ev = events[r.Intn(len(events))]
		}

		// [З3-скип] Нельзя купить билет на отменённое событие.
		if ev.Status == "cancelled" {
			continue
		}

		// [З3-веса] Было statuses[r.Intn(len(statuses))].
		// Стало: pick по весам — paid доминирует.
		status := pick(r, orderStatus, orderStatusW)
		nTickets := 1 + r.Intn(5)

		// [З3-сгущение] Было равномерное -r.Int63n(30 дней).
		// Стало: 50% заказов — в последнюю неделю перед событием,
		// редкие — за месяц. daysBefore = u^2 * 30, плотнее к 0.
		daysBefore := int(math.Pow(r.Float64(), 2.0) * 30)
		created := ev.Datetime.Add(-time.Duration(daysBefore) * 24 * time.Hour)
		if created.After(time.Now().UTC()) {
			created = time.Now().UTC()
		}
		total := ev.Price * float64(nTickets)

		var orderID int64
		if err := ordStmt.QueryRow(
			created, status, total,
			userIDs[r.Intn(len(userIDs))], ev.ID,
		).Scan(&orderID); err != nil {
			log.Fatalf("insert order: %v", err)
		}
		ordersTotal++

		for j := 0; j < nTickets; j++ {
			// [З3-веса] Статус билета согласован со статусом заказа.
			// Для paid — pick между valid|used по весам,
			// для остальных — жёсткая связка.
			ts := "valid"
			switch status {
			case "cancelled":
				ts = "cancelled"
			case "refunded":
				ts = "returned"
			case "paid":
				ts = pick(r, ticketStatus[:2], ticketStatusW[:2])
			}
			if _, err := tkStmt.Exec(ev.Price, ts, orderID); err != nil {
				log.Fatalf("insert ticket: %v", err)
			}
			ticketsTotal++
		}
	}
	log.Printf("orders: %d, tickets: %d", ordersTotal, ticketsTotal)
}
