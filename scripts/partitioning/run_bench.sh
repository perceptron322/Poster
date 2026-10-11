#!/usr/bin/env bash
# Прогоняет одинаковую нагрузку pgbench по orders_plain / orders_range / orders_hash.
# Каждый сценарий из bench/ — отдельный прогон, плюс смешанный (mixed).
# Результат — markdown-таблица в results.md.
#
# Переменные окружения: DURATION (сек, по умолчанию 30), CLIENTS (8), JOBS (4),
# TABLES, SCENARIOS (списки через пробел), RESULTS (файл результата).
set -euo pipefail
export LC_NUMERIC=C   # printf должен понимать точку в дробях
cd "$(dirname "$0")"

DURATION=${DURATION:-30}
CLIENTS=${CLIENTS:-8}
JOBS=${JOBS:-4}
TABLES=(${TABLES:-orders_plain orders_range orders_hash})
SCENARIOS=(${SCENARIOS:-by_user by_id by_period mixed insert})   # insert последним: он добавляет строки
RESULTS=${RESULTS:-results.md}
MIX="by_user@50 by_id@30 insert@15 by_period@5"

DC="docker compose -f ../../docker-compose.yml"
PSQL="$DC exec -T db psql -U poster -d poster -Atq"

# Параметры нагрузки берём из данных, чтобы все таблицы получали одинаковые значения.
read -r UMIN UMAX < <($PSQL -F' ' -c "SELECT min(user_id), max(user_id) FROM users")
EMAX=$($PSQL -c "SELECT max(event_id) FROM events")
OMAX=$($PSQL -c "SELECT max(order_id) FROM orders")
read -r T0 NDAYS < <($PSQL -F' ' -c "
    SELECT extract(epoch FROM date_trunc('day', min(created_at)))::bigint,
           (max(created_at)::date - min(created_at)::date) + 1
    FROM orders")
VARS="-D umin=$UMIN -D umax=$UMAX -D emax=$EMAX -D omax=$OMAX -D t0=$T0 -D ndays=$NDAYS"

# Шаблоны с подставленным именем таблицы кладём в контейнер.
for t in "${TABLES[@]}"; do
    for f in bench/*.sql; do
        sed "s/__T__/$t/g" "$f" | $DC exec -T db sh -c "mkdir -p /tmp/bench && cat > /tmp/bench/${t}_$(basename "$f")"
    done
done

pgbench() {   # $1 = таблица, $2 = сценарий, $3 = длительность
    local files
    if [ "$2" = mixed ]; then
        files=$(for s in $MIX; do echo -n "-f /tmp/bench/${1}_${s%@*}.sql@${s#*@} "; done)
    else
        files="-f /tmp/bench/${1}_$2.sql"
    fi
    # synchronous_commit=off: коммит не ждёт fsync WAL. Иначе вставки упираются
    # в диск хоста, и разброс между прогонами (в разы) скрывает разницу стратегий.
    $DC exec -T -e PGOPTIONS='-c synchronous_commit=off' db pgbench -U poster -d poster -n -M prepared \
        -c "$CLIENTS" -j "$JOBS" -T "$3" $VARS $files 2>&1
}

{
    echo "| Сценарий | Таблица | TPS | Средняя задержка, мс |"
    echo "|---|---|---:|---:|"
} > "$RESULTS"

for s in "${SCENARIOS[@]}"; do
    for t in "${TABLES[@]}"; do
        echo ">> $s / $t" >&2
        [ "$s" != insert ] && pgbench "$t" "$s" 5 >/dev/null   # прогрев кэша
        $PSQL -c CHECKPOINT   # одинаковое состояние WAL/буферов перед каждым замером
        out=$(pgbench "$t" "$s" "$DURATION")
        tps=$(grep -oP 'tps = \K[0-9.]+' <<<"$out" | head -1)
        lat=$(grep -oP 'latency average = \K[0-9.]+' <<<"$out" | head -1)
        printf '| %s | %s | %.0f | %.3f |\n' "$s" "$t" "$tps" "$lat" | tee -a "$RESULTS" >&2
    done
done

echo "Готово: $(pwd)/$RESULTS" >&2
