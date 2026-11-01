#!/bin/sh
set -eu

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_ADMIN_USER:?POSTGRES_ADMIN_USER is required}"
: "${POSTGRES_ADMIN_PASSWORD:?POSTGRES_ADMIN_PASSWORD is required}"
: "${APPLICATION_USER:?APPLICATION_USER is required}"
: "${APPLICATION_PASSWORD:?APPLICATION_PASSWORD is required}"
: "${ANALYST_USER:?ANALYST_USER is required}"
: "${ANALYST_PASSWORD:?ANALYST_PASSWORD is required}"

export PGPASSWORD="$POSTGRES_ADMIN_PASSWORD"

leader=""
attempt=0

echo "Ожидаем доступного лидера Patroni..."

while [ "$attempt" -lt 60 ]; do
    for host in patroni1 patroni2; do
        if result=$(
            psql -h "$host" -U "$POSTGRES_ADMIN_USER" -d postgres \
                -tA -v ON_ERROR_STOP=1 \
                -c 'SELECT NOT pg_is_in_recovery()' 2>/dev/null
        ) && [ "$result" = "t" ]; then
            leader="$host"
            break
        fi
    done

    [ -n "$leader" ] && break
    attempt=$((attempt + 1))
    sleep 2
done

if [ -z "$leader" ]; then
    echo "Ошибка: лидер Patroni не найден за 120 секунд." >&2
    exit 1
fi

echo "Лидер найден: $leader"

psql -h "$leader" -U "$POSTGRES_ADMIN_USER" -d postgres \
    -v ON_ERROR_STOP=1 \
    -v database_name="$POSTGRES_DB" <<'SQL'
SELECT format('CREATE DATABASE %I', :'database_name')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = :'database_name'
)
\gexec
SQL

psql -h "$leader" -U "$POSTGRES_ADMIN_USER" -d postgres \
    -v ON_ERROR_STOP=1 \
    -v application_user="$APPLICATION_USER" \
    -v application_password="$APPLICATION_PASSWORD" \
    -v analyst_user="$ANALYST_USER" \
    -v analyst_password="$ANALYST_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I', :'application_user')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = :'application_user'
)
\gexec

SELECT format(
    'ALTER ROLE %I WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L',
    :'application_user', :'application_password'
)
\gexec

SELECT format('CREATE ROLE %I', :'analyst_user')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = :'analyst_user'
)
\gexec

SELECT format(
    'ALTER ROLE %I WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L',
    :'analyst_user', :'analyst_password'
)
\gexec
SQL

psql -h "$leader" -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" \
    -v ON_ERROR_STOP=1 \
    -v database_name="$POSTGRES_DB" \
    -v admin_user="$POSTGRES_ADMIN_USER" \
    -v application_user="$APPLICATION_USER" \
    -v analyst_user="$ANALYST_USER" <<'SQL'
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION :"admin_user";
REVOKE ALL ON SCHEMA app FROM PUBLIC;

CREATE TABLE IF NOT EXISTS app.replication_probe (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    marker text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

GRANT CONNECT ON DATABASE :"database_name"
    TO :"application_user", :"analyst_user";

GRANT USAGE ON SCHEMA app TO :"application_user", :"analyst_user";

GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA app TO :"application_user";

GRANT USAGE, SELECT
    ON ALL SEQUENCES IN SCHEMA app TO :"application_user";

GRANT SELECT
    ON ALL TABLES IN SCHEMA app TO :"analyst_user";

ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user" IN SCHEMA app
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"application_user";

ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user" IN SCHEMA app
    GRANT USAGE, SELECT ON SEQUENCES TO :"application_user";

ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user" IN SCHEMA app
    GRANT SELECT ON TABLES TO :"analyst_user";
SQL

echo "Инициализация базы $POSTGRES_DB завершена."
