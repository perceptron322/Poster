PG_DSN ?= postgres://poster:secret@localhost:5433/poster?sslmode=disable

.PHONY: run clean

run:
	go run generate.go -config config.json

clean:
	psql "$(PG_DSN)" -c 'TRUNCATE tickets, orders, location_bookings, events, locations, users RESTART IDENTITY CASCADE;'