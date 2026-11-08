#!/bin/sh
# Межбазовая сверка PostgreSQL ↔ MongoDB.
# Mongo выгружает ключи страниц и отзывов в JSON, файл кладётся в контейнер db,
# сравнение выполняет scripts/mongo/cross_check.sql.
set -eu
cd "$(dirname "$0")/../.."

docker compose exec -T mongo sh -c 'mongosh --quiet \
  -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin "$MONGO_INITDB_DATABASE" /scripts/mongo/export_keys.js' \
| docker compose exec -T db sh -c 'cat > /tmp/mongo_keys.json'

docker compose exec -T db sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -q' < scripts/mongo/cross_check.sql
