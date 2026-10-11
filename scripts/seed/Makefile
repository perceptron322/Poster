PSQL = docker compose -f ../../docker-compose.yml exec -T db psql -U poster -d poster

.PHONY: run dev load measure verify clean

run:
	go run generate.go -config config.json

dev:
	@sed -i 's/"mode": *"[^"]*"/"mode": "dev"/' config.json
	go run generate.go -config config.json

load:
	@sed -i 's/"mode": *"[^"]*"/"mode": "load"/' config.json
	go run generate.go -config config.json

measure:
	$(PSQL) -c "SELECT 'tickets' t, count(*) FROM tickets UNION ALL SELECT 'orders', count(*) FROM orders UNION ALL SELECT 'events', count(*) FROM events;"

verify:
	$(PSQL) < verify.sql

clean:
	$(PSQL) -c 'TRUNCATE tickets, orders, location_bookings, events, locations, users RESTART IDENTITY CASCADE;'
