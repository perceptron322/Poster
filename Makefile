.PHONY: help db-up db-down db-logs db-shell migrate migrate-down migrate-create migrate-version reset run build

help:
	@echo "Доступные команды:"
	@echo "  make db-up            — поднять PostgreSQL в Docker"
	@echo "  make db-down          — остановить PostgreSQL"
	@echo "  make db-logs          — логи контейнера БД"
	@echo "  make db-shell         — psql внутри контейнера"
	@echo "  make migrate          — применить все миграции"
	@echo "  make migrate-down     — откатить последнюю миграцию"
	@echo "  make migrate-create   — создать миграцию (name=...)"
	@echo "  make migrate-version  — текущая версия схемы"
	@echo "  make reset            — сбросить БД и накатить миграции заново"
	@echo "  make run              — запустить приложение"
	@echo "  make build            — собрать бинарник"

DB_URL = postgres://poster:secret@localhost:5433/poster?sslmode=disable

db-up:
	docker compose up -d db

db-down:
	docker compose down

db-logs:
	docker compose logs -f db

db-shell:
	docker compose exec db psql -U poster -d poster

migrate:
	migrate -path migrations -database "$(DB_URL)" up

migrate-down:
	migrate -path migrations -database "$(DB_URL)" down 1

migrate-create:
	@if [ -z "$(name)" ]; then echo "Использование: make migrate-create name=create_users"; exit 1; fi
	migrate create -ext sql -dir migrations -seq $(name)

migrate-version:
	migrate -path migrations -database "$(DB_URL)" version

reset:
	docker compose down -v
	docker compose up -d db
	@sleep 3
	make migrate

run:
	go run cmd/api/main.go

build:
	go build -o bin/api cmd/api/main.go