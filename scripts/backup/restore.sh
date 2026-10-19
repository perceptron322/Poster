#!/bin/sh
# Восстанавливает бэкап в чистый экземпляр PostgreSQL (сервис restore, профиль restore)
# и сверяет результат с исходной БД (контейнер db) через compare.sql.
#
# Использование: sh scripts/backup/restore.sh [файл.dump]   (по умолчанию — самый свежий)
set -eu
cd "$(dirname "$0")/../.."

user=${POSTGRES_USER:-poster}
db=${POSTGRES_DB:-poster}
dir=${BACKUP_DIR:-backups}

dump=${1:-$(ls -t "$dir"/*.dump 2>/dev/null | head -n1)}
[ -n "$dump" ] && [ -f "$dump" ] || { echo "Нет файла бэкапа: сначала make backup"; exit 1; }
base=${dump%.dump}
roles=$base.roles.sql

echo "== Проверка контрольных сумм"
(cd "$(dirname "$dump")" && sha256sum -c "$(basename "$base").sha256")

echo "== Чистый экземпляр PostgreSQL"
# rm -v удаляет и анонимный том с данными: каждый запуск начинается с пустого кластера.
docker compose --profile restore rm -fsv restore >/dev/null 2>&1 || true
docker compose --profile restore up -d --wait restore

restore_psql() {
    docker compose exec -T restore psql -U "$user" -v ON_ERROR_STOP=1 -q "$@"
}

if [ "$(restore_psql -d postgres -Atc "SELECT count(*) FROM pg_database WHERE datname = '$db'")" != 0 ]; then
    echo "В новом экземпляре уже есть база $db — он не чистый"; exit 1
fi

echo "== Восстановление ролей"
# Суперпользователь уже создан при инициализации контейнера, его CREATE ROLE пропускаем.
grep -vx "CREATE ROLE $user;" "$roles" | restore_psql -d postgres

echo "== Восстановление базы $db"
docker compose cp "$dump" restore:/tmp/restore.dump
# -C создаёт базу из бэкапа, --exit-on-error останавливается на первой ошибке.
docker compose exec -T restore pg_restore -U "$user" -d postgres -C --exit-on-error /tmp/restore.dump
docker compose exec -T restore rm /tmp/restore.dump

echo "== Сверка с исходной БД"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
docker compose exec -T db psql -U "$user" -d "$db" -At -v ON_ERROR_STOP=1 < scripts/backup/compare.sql > "$tmp/source.txt"
restore_psql -d "$db" -At < scripts/backup/compare.sql > "$tmp/restored.txt"

if diff -u "$tmp/source.txt" "$tmp/restored.txt"; then
    echo
    grep '^table|' "$tmp/restored.txt" | awk -F'|' '{ printf "  %-20s %10s строк\n", $2, $3 }'
    echo "OK: восстановленная БД совпадает с исходной (данные, ограничения, индексы, роли, права)"
    echo "Экземпляр: localhost:5435, остановить — make restore-down"
else
    echo "ОШИБКА: восстановленная БД отличается от исходной (см. diff выше)"
    exit 1
fi
