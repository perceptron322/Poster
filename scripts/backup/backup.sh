#!/bin/sh
# Логическая резервная копия БД из контейнера db:
#   <имя>.roles.sql — роли кластера (pg_dumpall --roles-only, с хешами паролей);
#   <имя>.dump      — база в custom-формате (pg_dump -Fc);
#   <имя>.sha256    — контрольные суммы обоих файлов.
# Файлы содержат хеши паролей и данные пользователей: каталог в .gitignore, права 600.
#
# Переменные окружения: POSTGRES_USER, POSTGRES_DB, BACKUP_DIR (по умолчанию backups).
set -eu
cd "$(dirname "$0")/../.."

user=${POSTGRES_USER:-poster}
db=${POSTGRES_DB:-poster}
dir=${BACKUP_DIR:-backups}
name="${db}_$(date +%Y%m%d_%H%M%S)"

umask 077
mkdir -p "$dir"

# Пишем во временные файлы, чтобы при ошибке не осталось обрезанного бэкапа.
trap 'rm -f "$dir/$name".*.tmp' EXIT

docker compose exec -T db pg_dumpall -U "$user" --roles-only > "$dir/$name.roles.sql.tmp"
docker compose exec -T db pg_dump -U "$user" -d "$db" -Fc > "$dir/$name.dump.tmp"

mv "$dir/$name.roles.sql.tmp" "$dir/$name.roles.sql"
mv "$dir/$name.dump.tmp" "$dir/$name.dump"
(cd "$dir" && sha256sum "$name.roles.sql" "$name.dump" > "$name.sha256")

# Архив должен читаться: pg_restore --list разбирает его оглавление.
entries=$(docker compose exec -T db pg_restore --list < "$dir/$name.dump" | grep -vc '^;')

echo "Бэкап создан: $dir/$name.dump ($(du -h "$dir/$name.dump" | cut -f1), объектов в оглавлении: $entries)"
echo "Роли:         $dir/$name.roles.sql"
