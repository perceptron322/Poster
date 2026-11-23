#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.mongo-rs-fault.yml"
PROJECT="sprint06-tx-fault-demo"
CONTAINER=""

compose() {
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" "$@"
}

cleanup() {
  compose down --volumes >/dev/null 2>&1 || true
}
trap cleanup EXIT

compose up -d --wait
CONTAINER="$(compose ps -q txfault1)"
if [[ -z "$CONTAINER" ]]; then
  echo "Не удалось найти контейнер txfault1" >&2
  exit 1
fi

docker exec "$CONTAINER" mongosh --quiet --eval '
rs.initiate({
  _id: "txFaultRS",
  members: [
    {_id: 0, host: "txfault1:27017"},
    {_id: 1, host: "txfault2:27017"},
    {_id: 2, host: "txfault3:27017"}
  ]
})'

PRIMARY_READY=false
for _ in {1..60}; do
  if docker exec "$CONTAINER" mongosh --quiet --eval 'quit(db.hello().isWritablePrimary ? 0 : 1)' >/dev/null 2>&1; then
    PRIMARY_READY=true
    break
  fi
  sleep 1
done
if [[ "$PRIMARY_READY" != true ]]; then
  echo "Не удалось дождаться Primary в тестовом Replica Set" >&2
  exit 1
fi

MONGO_RS_CONTAINER="$CONTAINER" \
MONGO_RS_URI='mongodb://txfault1:27017,txfault2:27017,txfault3:27017/?replicaSet=txFaultRS' \
  bash "$ROOT_DIR/scripts/mongo-rs/run-transaction-demo.sh" server-retry

echo "Изолированный Replica Set будет остановлен, его тестовые volumes удалятся."
