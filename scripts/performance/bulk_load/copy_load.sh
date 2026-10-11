#!/usr/bin/env bash
set -euo pipefail

docker compose exec -T db psql -U poster -d poster -v ON_ERROR_STOP=1 \
  -c "TRUNCATE TABLE bulk_load_benchmark;"

start=$(date +%s.%N)

docker compose exec -T db psql -U poster -d poster -v ON_ERROR_STOP=1 \
  -c "\copy bulk_load_benchmark (id, name, amount, created_at) FROM STDIN WITH (FORMAT csv)" \
  < scripts/performance/bulk_load/data.csv

end=$(date +%s.%N)

python3 -c "print(f'COPY: 50000 rows in {float(\"$end\") - float(\"$start\"):.3f} seconds')"
