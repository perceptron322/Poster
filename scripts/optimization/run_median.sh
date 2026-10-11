#!/usr/bin/env bash
# Медианное время выполнения запросов до и после индексов.
# Каждый запрос: WARMUP прогревочных запусков (не учитываются) + RUNS замеров,
# берётся Execution Time из EXPLAIN (ANALYZE, BUFFERS).
# Планы последнего запуска сохраняются в docs/performance/*_median_{before,after}.txt.
#
# Переменные окружения: DB (poster_bench_load), RUNS (15), WARMUP (3).
set -euo pipefail
export LC_NUMERIC=C
cd "$(dirname "$0")"

DB=${DB:-poster_bench_load}
RUNS=${RUNS:-15}
WARMUP=${WARMUP:-3}
OUT=../../docs/performance
PSQL="docker compose -f ../../docker-compose.yml exec -T db psql -U poster -d $DB -v ON_ERROR_STOP=1"

measure() {   # $1 = файл запроса, $2 = before|after
    local name=${1%.sql} times=() plan
    for ((i = 0; i < WARMUP; i++)); do $PSQL -q < "$1" >/dev/null; done
    for ((i = 0; i < RUNS; i++)); do
        plan=$($PSQL < "$1")
        times+=("$(grep -oP 'Execution Time: \K[0-9.]+' <<<"$plan")")
    done
    echo "$plan" > "$OUT/${name}_median_$2.txt"
    printf '%s\n' "${times[@]}" | sort -n | awk -v q="$name" -v s="$2" '
        { t[NR] = $1 }
        END {
            med = (NR % 2) ? t[(NR + 1) / 2] : (t[NR / 2] + t[NR / 2 + 1]) / 2
            printf "| %s | %s | %.3f | %.3f | %.3f |\n", q, s, med, t[1], t[NR]
        }'
}

echo "| Запрос | Индексы | Медиана, мс | Мин, мс | Макс, мс |"
echo "|---|---|---:|---:|---:|"

$PSQL -q < drop_indexes.sql
for q in 01_catalog.sql 02_revenue.sql; do measure "$q" before; done

$PSQL -q < indexes.sql
for q in 01_catalog.sql 02_revenue.sql; do measure "$q" after; done
