#!/usr/bin/env bash
set -Eeuo pipefail

# Загружаем локальные настройки, не выводя пароли.
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

: "${APP_USER_PASSWORD:?Set APP_USER_PASSWORD in .env}"
: "${ANALYST_USER_PASSWORD:?Set ANALYST_USER_PASSWORD in .env}"
: "${APP_ADMIN_PASSWORD:?Set APP_ADMIN_PASSWORD in .env}"

# Выполняет запрос, который обязан завершиться успешно.
run_ok() {
  local role="$1"
  local password="$2"
  local sql="$3"

  docker compose exec -T -e PGPASSWORD="$password" db \
    psql -X -v ON_ERROR_STOP=1 -U "$role" -d poster -c "$sql"
}

# Выполняет запрос, который обязан быть отклонён PostgreSQL.
run_denied() {
  local role="$1"
  local password="$2"
  local sql="$3"

  if docker compose exec -T -e PGPASSWORD="$password" db \
      psql -X -v ON_ERROR_STOP=1 -U "$role" -d poster -c "$sql"; then
    echo "ОШИБКА: роль $role неожиданно выполнила запрещённую операцию" >&2
    return 1
  else
    echo "Ожидаемый отказ подтверждён."
  fi
}

echo "=== 1. Приложение (app_user) ==="
echo "Чтение: разрешено"
run_ok app_user "$APP_USER_PASSWORD" "SELECT count(*) FROM events;"

echo "Вставка: разрешена"
run_ok app_user "$APP_USER_PASSWORD" \
  "INSERT INTO users (name, email, role) VALUES ('App Test', 'app_test@example.com', 'customer');"

echo "Удаление: разрешено"
run_ok app_user "$APP_USER_PASSWORD" \
  "DELETE FROM users WHERE email = 'app_test@example.com';"

echo "Создание таблицы: запрещено"
run_denied app_user "$APP_USER_PASSWORD" "CREATE TABLE test (id int);"

echo "Чтение pg_shadow: запрещено"
run_denied app_user "$APP_USER_PASSWORD" "SELECT * FROM pg_shadow;"

echo "=== 2. Аналитик (analyst_user) ==="
echo "Чтение: разрешено"
run_ok analyst_user "$ANALYST_USER_PASSWORD" "SELECT count(*) FROM orders;"

echo "Агрегация: разрешена"
run_ok analyst_user "$ANALYST_USER_PASSWORD" \
  "SELECT status, count(*) FROM orders GROUP BY status;"

echo "Запись: запрещена"
run_denied analyst_user "$ANALYST_USER_PASSWORD" \
  "INSERT INTO users (name, email, role) VALUES ('Hacker', 'h@x.com', 'customer');"

echo "=== 3. Администратор (admin_user) ==="
echo "DDL: разрешено"
run_ok admin_user "$APP_ADMIN_PASSWORD" "CREATE TABLE test_admin (id int);"
run_ok admin_user "$APP_ADMIN_PASSWORD" "DROP TABLE test_admin;"

echo "DML: разрешено"
run_ok admin_user "$APP_ADMIN_PASSWORD" \
  "INSERT INTO users (name, email, role) VALUES ('Admin', 'admin_test@example.com', 'customer');"
run_ok admin_user "$APP_ADMIN_PASSWORD" \
  "DELETE FROM users WHERE email = 'admin_test@example.com';"

echo "Все проверки ролей завершены успешно."
