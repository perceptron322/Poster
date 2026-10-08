package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"os"
	"time"

	_ "github.com/lib/pq"
)

type Config struct {
	Seed int64  `json:"seed"`
	Dsn  string `json:"dsn"`
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

func main() {
	var cfgPath string
	flag.StringVar(&cfgPath, "config", "config.json", "path to config.json")
	flag.Parse()

	cfg := loadConfig(cfgPath)

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

	eventIDs := genEvents(tx, cfg, userIDs, locIDs)
	log.Printf("events: %d", len(eventIDs))

	if err := tx.Commit(); err != nil {
		log.Fatal(err)
	}
	log.Printf("seed=%d done", cfg.Seed)
}

// ---------- users ----------

func genUsers(tx *sql.Tx, cfg Config) []int64 {
	r := rngFor(cfg.Seed, "users")
	n := 1_000

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
		// пока без весов — три роли поровну
		role := []string{"guest", "customer", "organizer"}[r.Intn(3)]
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
		cap := 50 + r.Intn(950) // пока равномерно
		city := cities[r.Intn(len(cities))]
		name := fmt.Sprintf("Venue %d", i)
		addr := fmt.Sprintf("%s, street %d", city, i)
		if err := stmt.QueryRow(name, addr, cap).Scan(&id); err != nil {
			log.Fatalf("insert location: %v", err)
		}
		ids = append(ids, id)
	}
	return ids
}

// ---------- events ----------

func genEvents(tx *sql.Tx, cfg Config, userIDs, locIDs []int64) []int64 {
	r := rngFor(cfg.Seed, "events")
	n := 500
	types := []string{"concert", "lecture", "theatre", "festival", "other"}

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
	ids := make([]int64, 0, n)
	for i := 0; i < n; i++ {
		var id int64
		start := windowStart.Add(time.Duration(r.Int63n(60*24*3600)) * time.Second)
		durMin := 60 + r.Intn(120)
		durStr := fmt.Sprintf("%d minutes", durMin)
		status := "published"
		if start.Before(now) {
			status = "finished"
		}
		price := float64(500 + r.Intn(4500))
		err := stmt.QueryRow(
			fmt.Sprintf("Event %d", i),
			"description "+fmt.Sprint(i),
			fmt.Sprintf("http://img/%d.jpg", i),
			start, durStr, types[r.Intn(len(types))],
			price, status,
			userIDs[r.Intn(len(userIDs))],
			locIDs[r.Intn(len(locIDs))],
		).Scan(&id)
		if err != nil {
			log.Fatalf("insert event: %v", err)
		}
		ids = append(ids, id)
	}
	return ids
}
