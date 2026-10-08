PG_DSN ?= postgres://poster:secret@localhost:5433/poster?sslmode=disable

.PHONY: run dev load measure clean

run:
	go run generate.go -config config.json

dev:
	@sed -i 's/"mode": *"[^"]*"/"mode": "dev"/' config.json
	go run generate.go -config config.json

load:
	@sed -i 's/"mode": *"[^"]*"/"mode": "load"/' config.json
	go run generate.go -config config.json

measure:
	psql "$(PG_DSN)" -c "SELECT 'tickets' t, count(*) FROM tickets UNION ALL SELECT 'orders', count(*) FROM orders UNION ALL SELECT 'events', count(*) FROM events;"

clean:
	psql "$(PG_DSN)" -c 'TRUNCATE tickets, orders, location_bookings, events, locations, users RESTART IDENTITY CASCADE;'