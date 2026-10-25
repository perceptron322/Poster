.PHONY: help setup env db-up db-down db-logs db-shell migrate migrate-down migrate-create migrate-version reset run build

-include .env
export

POSTGRES_HOST     ?= localhost
POSTGRES_PORT     ?= 5433
POSTGRES_DB       ?= poster
POSTGRES_USER     ?= poster
POSTGRES_SSLMODE  ?= require

DB_URL ?= $(if $(DATABASE_URL),$(DATABASE_URL),postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@$(POSTGRES_HOST):$(POSTGRES_PORT)/$(POSTGRES_DB)?sslmode=$(POSTGRES_SSLMODE))

.DEFAULT_GOAL := help

check-env:
	@if [ -z "$(DATABASE_URL)" ] && [ -z "$(POSTGRES_PASSWORD)" ]; then \
		echo "POSTGRES_PASSWORD не задан: cp .env.example .env и заполните значения"; exit 1; \
	fi

help:
	@echo "Доступные команды:"
	@echo "  make setup            — первый запуск: .env, pre-commit хук, БД и миграции"
	@echo "  make env              — создать/дополнить .env из .env.example случайными паролями"
	@echo "  make ha-lab-env       — то же для scripts/ha-lab/.env"
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
	@echo "  make backup           — резервная копия БД и ролей в backups/"
	@echo "  make restore          — восстановить бэкап в чистый PostgreSQL и сверить (file=...)"
	@echo "  make restore-down     — удалить экземпляр восстановления"
	@echo "  make secrets-scan     — проверить репозиторий на утёкшие секреты (gitleaks)"
	@echo ""
	@echo "HA-стенд (scripts/ha-lab, primary :55432, replica :55433):"
	@echo "  make ha-up            — поднять primary и replica, дождаться streaming"
	@echo "  make ha-status        — роли узлов и состояние репликации"
	@echo "  make ha-lsn           — LSN на узлах и отставание реплики"
	@echo "  make ha-restart       — перезапустить replica и дождаться streaming"
	@echo "  make ha-rebuild       — пересоздать replica из нового base backup"
	@echo "  make ha-test          — автотесты репликации"
	@echo "  make ha-logs          — последние логи узлов"
	@echo "  make ha-down          — остановить стенд (данные сохраняются)"
	@echo "  make ha-clean         — остановить стенд и удалить его тома"

env:
	@sh scripts/env-init.sh .env.example .env

ha-lab-env:
	@sh scripts/env-init.sh scripts/ha-lab/.env.example scripts/ha-lab/.env

setup: env
	@if command -v pre-commit >/dev/null; then pre-commit install; \
	else echo "pre-commit не установлен: pip install pre-commit && pre-commit install"; fi
	@command -v migrate >/dev/null || { echo "нужен golang-migrate: https://github.com/golang-migrate/migrate"; exit 1; }
	$(MAKE) db-up
	$(MAKE) migrate

db-up:
	docker compose up -d --wait db

db-down:
	docker compose down

db-logs:
	docker compose logs -f db

db-shell:
	docker compose exec db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

create-roles:
	@if [ -z "$$APP_ADMIN_PASSWORD" ] || [ -z "$$APP_USER_PASSWORD" ] || [ -z "$$ANALYST_USER_PASSWORD" ]; then \
		echo "Пароли ролей не заданы: выполните make env"; exit 1; \
	fi
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
	$(MAKE) db-up
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

backup:
	@sh scripts/backup/backup.sh

restore:
	@sh scripts/backup/restore.sh $(file)

restore-down:
	docker compose --profile restore rm -fsv restore

GITLEAKS_IMAGE = ghcr.io/gitleaks/gitleaks:v8.21.2

secrets-scan:
	docker run --rm -v "$(CURDIR):/repo:z" $(GITLEAKS_IMAGE) git /repo --config /repo/.gitleaks.toml --gitleaks-ignore-path /repo/.gitleaksignore --redact -v

.PHONY: seed scenarios negatives property-tests test-all check-env secrets-scan print-db-url create-roles ha-lab-env backup restore restore-down

HA = sh scripts/ha-lab/ha.sh

ha-up:
	@$(HA) up

ha-status:
	@$(HA) status

ha-lsn:
	@$(HA) lsn

ha-restart:
	@$(HA) restart

ha-rebuild:
	@$(HA) rebuild

ha-test:
	@$(HA) test

ha-logs:
	@$(HA) logs

ha-down:
	@$(HA) down

ha-clean:
	@$(HA) clean

.PHONY: ha-up ha-status ha-lsn ha-restart ha-rebuild ha-test ha-logs ha-down ha-clean
