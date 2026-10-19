#!/usr/bin/env bash
set -Eeuo pipefail

echo "=== 1. Подготовка тестовой таблицы и включение RLS ==="
docker compose exec -T db psql -U poster -d poster -c "
DROP TABLE IF EXISTS rls_test_table;
CREATE TABLE rls_test_table (
    id SERIAL PRIMARY KEY,
    owner_name TEXT,
    secret_data TEXT
);
ALTER TABLE rls_test_table ENABLE ROW LEVEL SECURITY;
"

echo "=== 2. Создание политики RLS ==="
docker compose exec -T db psql -U poster -d poster -c "
CREATE POLICY rls_isolation_policy ON rls_test_table
FOR ALL
TO PUBLIC
USING (owner_name = CURRENT_USER)
WITH CHECK (owner_name = CURRENT_USER);
"

echo "=== 3. Создание тестовых ролей и выдача прав ==="
docker compose exec -T db psql -U poster -d poster -c "
DROP ROLE IF EXISTS alice;
DROP ROLE IF EXISTS bob;
CREATE ROLE alice WITH LOGIN;
CREATE ROLE bob WITH LOGIN;

-- Выдаем базовые права на таблицу и последовательность
GRANT SELECT, INSERT, UPDATE, DELETE ON rls_test_table TO alice, bob;
GRANT USAGE, SELECT ON SEQUENCE rls_test_table_id_seq TO alice, bob;
"

echo "=== 4. Вставка тестовых данных от имени разных пользователей ==="
docker compose exec -T db psql -U poster -d poster -c "
SET SESSION AUTHORIZATION alice;
INSERT INTO rls_test_table (owner_name, secret_data) VALUES ('alice', 'Секретные данные Алисы');

SET SESSION AUTHORIZATION bob;
INSERT INTO rls_test_table (owner_name, secret_data) VALUES ('bob', 'Секретные данные Боба');

RESET SESSION AUTHORIZATION;
"

echo "=== 5. Проверка изоляции данных (Тест RLS) ==="
echo "--- Данные, которые видит пользователь alice ---"
ALICE_DATA=$(docker compose exec -T db psql -U poster -d poster -q -t -A -c "SET SESSION AUTHORIZATION alice; SELECT secret_data FROM rls_test_table ORDER BY id;" | xargs)
echo "Результат: '$ALICE_DATA'"

echo "--- Данные, которые видит пользователь bob ---"
BOB_DATA=$(docker compose exec -T db psql -U poster -d poster -q -t -A -c "SET SESSION AUTHORIZATION bob; SELECT secret_data FROM rls_test_table ORDER BY id;" | xargs)
echo "Результат: '$BOB_DATA'"

echo "=== 6. Валидация результатов ==="
if [[ "$ALICE_DATA" == "Секретные данные Алисы" ]] && [[ "$BOB_DATA" == "Секретные данные Боба" ]]; then
    echo ""
    echo "✅ ИТОГ: Тест RLS пройден успешно! Пользователи видят только свои данные, изоляция работает корректно."
else
    echo ""
    echo "❌ ОШИБКА: Тест RLS провален. Изоляция данных не работает."
    exit 1
fi