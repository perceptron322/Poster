package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math"
	"math/rand"
	"net/url"
	"os"
	"sort"
	"time"

	_ "github.com/lib/pq"
)

type Config struct {
	Seed       int64  `json:"seed"`
	Mode       string `json:"mode"`
	Database   string `json:"database"`
	Dsn        string `json:"-"`
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
	c.Dsn = dsnFromEnv(c.Database)
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

func dsnFromEnv(database string) string {
	password := os.Getenv("POSTGRES_PASSWORD")
	if password == "" {
		log.Fatal("POSTGRES_PASSWORD не задан: cp .env.example .env в корне репозитория")
	}
	if database == "" {
		database = envOr("POSTGRES_DB", "poster")
	}
	u := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(envOr("POSTGRES_USER", "poster"), password),
		Host:     envOr("POSTGRES_HOST", "localhost") + ":" + envOr("POSTGRES_PORT", "5433"),
		Path:     "/" + database,
		RawQuery: "sslmode=" + envOr("POSTGRES_SSLMODE", "require"),
	}
	return u.String()
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

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

type eventRow struct {
	ID         int64
	UserID     int64
	LocationID int64
	Datetime   time.Time
	Duration   time.Duration
	Price      float64
	Status     string
}

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
	// Окно событий: от 60 дней в прошлом до 60 дней в будущем
	windowStart := now.AddDate(0, 0, -60)
	windowEnd := now.AddDate(0, 0, 60)
	windowSecs := int64(windowEnd.Sub(windowStart).Seconds())

	rows := make([]eventRow, 0, n)
	for i := 0; i < n; i++ {
		// Равномерное распределение по всему окну
		offset := r.Int63n(windowSecs)
		start := windowStart.Add(time.Duration(offset) * time.Second)

		durMin := 60 + r.Intn(120)
		dur := time.Duration(durMin) * time.Minute
		durStr := fmt.Sprintf("%d minutes", durMin)

		// Логика статуса: прошедшие -> finished/cancelled, будущие -> published/cancelled
		var status string
		if start.Before(now) {
			status = pick(r, []string{"finished", "cancelled"}, []float64{90, 10})
		} else {
			status = pick(r, []string{"published", "cancelled"}, []float64{90, 10})
		}

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
			Status:     status,
		})
	}
	return rows
}

// ---------- location_bookings ----------

func genBookings(tx *sql.Tx, cfg Config, events []eventRow) {
	// [З3-EXCLUDE] Сортируем по возрастанию start_time.
	sort.Slice(events, func(i, j int) bool {
		return events[i].Datetime.Before(events[j].Datetime)
	})

	type interval struct{ start, end time.Time }
	busy := make(map[int64][]interval)

	stmt, err := tx.Prepare(`
		INSERT INTO location_bookings (location_id, event_id, start_time, end_time)
		VALUES ($1,$2,$3,$4)`)
	if err != nil {
		log.Fatal(err)
	}
	defer stmt.Close()

	inserted, skippedCancelled, skippedOverlap := 0, 0, 0

	for _, e := range events {
		// Отменённое событие площадку не занимает.
		if e.Status == "cancelled" {
			skippedCancelled++
			continue
		}

		eStart := e.Datetime
		eEnd := e.Datetime.Add(e.Duration)

		// [З3-EXCLUDE] Проверка пересечения с уже занятыми слотами.
		// Два интервала пересекаются, если eStart < b.end && b.start < eEnd.
		overlap := false
		for _, b := range busy[e.LocationID] {
			if eStart.Before(b.end) && b.start.Before(eEnd) {
				overlap = true
				break
			}
		}
		if overlap {
			skippedOverlap++
			continue
		}

		if _, err := stmt.Exec(e.LocationID, e.ID, eStart, eEnd); err != nil {
			log.Fatalf("insert booking: %v", err)
		}
		busy[e.LocationID] = append(busy[e.LocationID], interval{eStart, eEnd})
		inserted++
	}

	log.Printf("bookings: inserted=%d skipped_cancelled=%d skipped_overlap=%d",
		inserted, skippedCancelled, skippedOverlap)
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
	now := time.Now().UTC()

	for i := 0; i < targetOrders; i++ {
		var ev eventRow
		if r.Float64() < 0.8 {
			ev = events[zipfIndex(r, len(events), 1.2)]
		} else {
			ev = events[r.Intn(len(events))]
		}

		if ev.Status == "cancelled" {
			continue
		}

		status := pick(r, orderStatus, orderStatusW)
		nTickets := 1 + r.Intn(5)

		// Логика даты заказа:
		// 1. Заказ должен быть создан ДО начала события (минимум за час).
		maxCreated := ev.Datetime.Add(-time.Hour)
		// 2. Заказ не может быть создан в будущем.
		if maxCreated.After(now) {
			maxCreated = now
		}

		// Окно создания заказов: последние 90 дней от текущего момента
		minCreated := now.AddDate(0, 0, -90)
		if minCreated.After(maxCreated) {
			// Если событие было очень давно, сдвигаем окно назад относительно события
			minCreated = maxCreated.AddDate(0, 0, -30)
		}

		windowSecs := int64(maxCreated.Sub(minCreated).Seconds())
		if windowSecs <= 0 {
			windowSecs = 1
		}
		offset := r.Int63n(windowSecs)
		created := minCreated.Add(time.Duration(offset) * time.Second)

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
