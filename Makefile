.PHONY: help setup env db-up db-down db-logs db-shell migrate migrate-down migrate-create migrate-version reset run build

-include .env.example
-include .env
export

POSTGRES_HOST     ?= localhost
POSTGRES_PORT     ?= 5433
POSTGRES_DB       ?= poster
POSTGRES_USER     ?= poster

DB_URL ?= $(if $(DATABASE_URL),$(DATABASE_URL),postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@$(POSTGRES_HOST):$(POSTGRES_PORT)/$(POSTGRES_DB)?sslmode=disable)

.DEFAULT_GOAL := help

check-env:
	@if [ -z "$(DATABASE_URL)" ] && [ -z "$(POSTGRES_PASSWORD)" ]; then \
		echo "POSTGRES_PASSWORD не задан: cp .env.example .env и заполните значения"; exit 1; \
	fi

help:
	@echo "Доступные команды:"
	@echo "  make setup            — первый запуск: .env, pre-commit хук, БД и миграции"
	@echo "  make env              — создать .env из .env.example со случайными паролями"
	@echo "  make db-up            — поднять PostgreSQL в Docker"
	@echo "  make db-down          — остановить PostgreSQL"
	@echo "  make db-logs          — логи контейнера БД"
	@echo "  make db-shell         — psql внутри контейнера"
	@echo "  make migrate          — применить все миграции"
	@echo "  make migrate-create   — создать миграцию (name=...)"
	@echo "  make migrate-version  — текущая версия схемы"
	@echo "  make reset            — сбросить БД и накатить миграции заново"
	@echo "  make create-roles     — создать роли БД (app, analyst, admin)"
	@echo "  make run              — запустить приложение"
	@echo "  make build            — собрать бинарник"
	@echo "  make print-db-url     — показать текущий DB_URL (без пароля)"
	@echo "  make queries          — выполнить пять бизнес-запросов из scripts/queries/"
	@echo "  make transactions     — выполнить транзакцию возврата билета из scripts/transactions/"
	@echo "  make secrets-scan     — проверить репозиторий на утёкшие секреты (gitleaks)"

env:
	@if [ -f .env ]; then \
		echo ".env уже есть, не трогаю"; \
	else \
		pw=$$(openssl rand -hex 16); \
		sed "s/change_me/$$pw/g" .env.example > .env; \
		chmod 600 .env; \
		echo ".env создан из .env.example, change_me заменены случайным значением"; \
	fi

setup: env
	@if command -v pre-commit >/dev/null; then pre-commit install; \
	else echo "pre-commit не установлен: pip install pre-commit && pre-commit install"; fi
	@command -v migrate >/dev/null || { echo "нужен golang-migrate: https://github.com/golang-migrate/migrate"; exit 1; }
	$(MAKE) db-up
	@for i in $$(seq 1 30); do docker compose exec -T db pg_isready -q && break; sleep 1; done
	$(MAKE) migrate

db-up:
	docker compose up -d db

db-down:
	docker compose down

db-logs:
	docker compose logs -f db

db-shell:
	docker compose exec db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

create-roles:
	docker compose exec -T db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) \
		-v admin_pass="$$APP_ADMIN_PASSWORD" \
		-v app_pass="$$APP_USER_PASSWORD" \
		-v analyst_pass="$$ANALYST_USER_PASSWORD" \
		-v ON_ERROR_STOP=1 < scripts/security/roles.sql

migrate: check-env
	@migrate -path migrations -database "$(DB_URL)" up

migrate-create:
	@if [ -z "$(name)" ]; then echo "Использование: make migrate-create name=create_users"; exit 1; fi
	migrate create -ext sql -dir migrations -seq $(name)

migrate-version: check-env
	@migrate -path migrations -database "$(DB_URL)" version

reset:
	docker compose down -v
	docker compose up -d db
	@sleep 3
	$(MAKE) migrate

run:
	go run cmd/api/main.go

build:
	go build -o bin/api cmd/api/main.go

print-db-url:
	@echo '$(DB_URL)' | sed -E 's#(://[^:/]+:)[^@]+@#\1****@#'

PSQL = docker compose exec -T db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -v ON_ERROR_STOP=1

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

queries:
	@for f in scripts/queries/*.sql; do \
	    echo "== $$f =="; \
	    $(PSQL) < $$f; \
	done

transactions:
	$(PSQL) < scripts/transactions/refund_one_ticket.sql

property-tests:
	@echo "== Property-based tests =="
	@$(PSQL) < scripts/property/schema_constraints.sql
	@echo "✅ Все property-based тесты прошли"

pgstat-reset:
	@$(PSQL) < scripts/performance/reset_stats.sql

pgstat-report:
	@$(PSQL) < scripts/performance/report.sql

pgstat-report-save:
	@mkdir -p docs/performance
	@$(PSQL) < scripts/performance/report.sql > docs/performance/pgstat-report.txt
	@echo "Отчёт сохранён: docs/performance/pgstat-report.txt"

test-all: seed scenarios negatives property-tests
	@echo "✅ Все сценарии и негативные тесты прошли"

GITLEAKS_IMAGE = ghcr.io/gitleaks/gitleaks:v8.21.2

secrets-scan:
	docker run --rm -v "$(CURDIR):/repo:Z" $(GITLEAKS_IMAGE) git /repo --config /repo/.gitleaks.toml --gitleaks-ignore-path /repo/.gitleaksignore --redact -v

.PHONY: seed scenarios negatives property-tests test-all check-env secrets-scan print-db-url