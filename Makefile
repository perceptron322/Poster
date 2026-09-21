.PHONY: help db-up db-down db-logs db-shell migrate migrate-down migrate-create migrate-version reset run build

-include .env.example
export

POSTGRES_HOST     ?= localhost
POSTGRES_PORT     ?= 5433
POSTGRES_DB       ?= poster
POSTGRES_USER     ?= poster
POSTGRES_PASSWORD ?= secret

DB_URL ?= $(if $(DATABASE_URL),$(DATABASE_URL),postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@$(POSTGRES_HOST):$(POSTGRES_PORT)/$(POSTGRES_DB)?sslmode=disable)

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
	@echo "  make print-db-url     — показать текущий DB_URL"

db-up:
	docker compose up -d db

db-down:
	docker compose down

db-logs:
	docker compose logs -f db

db-shell:
	docker compose exec db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

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
	$(MAKE) migrate

run:
	go run cmd/api/main.go

build:
	go build -o bin/api cmd/api/main.go

PSQL = docker compose exec -T db psql -U poster -d poster -v ON_ERROR_STOP=1

seed:
	$(PSQL) < scripts/seed.sql

scenarios:
	@for f in scripts/scenarios/*.sql; do \
		echo "== $$f =="; \
		$(PSQL) < "$$f" || exit 1; \
	done

negatives:
	@fail=0; \
	for f in scripts/negative/*.sql; do \
		echo "== $$f =="; \
		if $(PSQL) -1 -f "/dev/stdin" < "$$f" >/dev/null 2>&1; then \
			echo "  ❌ ПРОВАЛ: не упало"; fail=1; \
		else \
			echo "  ✅ OK: ошибка получена"; \
		fi; \
	done; \
	exit $$fail

property-tests:
	@echo "== Property-based tests =="
	@$(PSQL) < scripts/property/schema_constraints.sql
	@echo "✅ Все property-based тесты прошли"
test-all: seed scenarios negatives property-tests
	@echo "✅ Все сценарии и негативные тесты прошли"

.PHONY: seed scenarios negatives property-tests test-all