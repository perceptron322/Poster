#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
mkdir -p docs/performance
RUNS=${RUNS:-11}
WARMUP=${WARMUP:-2}

docker compose exec -T -e RUNS="$RUNS" -e WARMUP="$WARMUP" mongo sh -c \
  'mongosh --quiet --norc -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin "$MONGO_INITDB_DATABASE" --file /scripts/mongo/optimization/bench.js' \
  > docs/performance/mongo_query_optimization.jsonl

python3 - <<'PY'
import json
from pathlib import Path

jsonl = Path('docs/performance/mongo_query_optimization.jsonl')
rows = [json.loads(line) for line in jsonl.read_text().splitlines() if line.strip()]
if len(rows) != 4:
    raise SystemExit(f'Ожидалось 4 результата (2 запроса × до/после), получено: {len(rows)}. См. вывод mongosh в {jsonl}')
lines = [
    '| Запрос | Этап | executionTimeMillis, медиана | totalDocsExamined, медиана | totalKeysExamined, медиана | Возвращено документов, медиана |',
    '|---|---|---:|---:|---:|---:|',
]
for row in rows:
    lines.append(f"| {row['query']} | {row['phase']} | {row['medianExecutionTimeMillis']} | {row['medianTotalDocsExamined']} | {row['medianTotalKeysExamined']} | {row['medianReturnedDocuments']} |")
summary = Path('docs/performance/mongo_query_optimization.md')
summary.write_text('\n'.join(lines) + '\n')
print('\n'.join(lines))
print(f'Планы и отдельные запуски: {jsonl}')
print(f'Таблица результатов: {summary}')
PY
