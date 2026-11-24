#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.mongo-rs-fault.yml"
PROJECT="sprint06-read-pref-$$-$RANDOM"
URI='mongodb://txfault1:27017,txfault2:27017,txfault3:27017/?replicaSet=txFaultRS'
HOST_BINARY="$(mktemp)"
CONTAINER_BINARY=/tmp/poster-read-preference

compose() {
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" "$@"
}

cleanup() {
  local status=$?
  rm -f "$HOST_BINARY"
  compose down --volumes || status=1
  exit "$status"
}
trap cleanup EXIT

node_eval() {
  local service="$1" expression="$2"
  compose exec -T "$service" mongosh \
    'mongodb://localhost:27017/?directConnection=true&serverSelectionTimeoutMS=1000' \
    --quiet --eval "$expression"
}

wait_for() {
  local service="$1" condition="$2"
  for _ in {1..60}; do
    if node_eval "$service" "quit(($condition) ? 0 : 1)" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "На узле $service не выполнено условие: $condition" >&2
  return 1
}

probe() {
  docker exec -e MONGO_URI="$URI" "$CLIENT" "$CONTAINER_BINARY" "$@"
}

(
  cd "$ROOT_DIR/cmd/bulk_test"
  GOOS=linux CGO_ENABLED=0 go build -o "$HOST_BINARY" ./read_preference
)

compose up -d --wait --wait-timeout 90
CLIENT="$(compose ps -q txfault3)"
docker cp "$HOST_BINARY" "$CLIENT:$CONTAINER_BINARY"

node_eval txfault1 'rs.initiate({
  _id: "txFaultRS",
  members: [
    {_id: 0, host: "txfault1:27017", priority: 2},
    {_id: 1, host: "txfault2:27017", tags: {node: "txfault2"}},
    {_id: 2, host: "txfault3:27017"}
  ]
})'
wait_for txfault1 'db.hello().isWritablePrimary'
node_eval txfault1 '
  print("MongoDB " + db.version());
  const demo = db.getSiblingDB("poster_read_preference_demo");
  demo.event_pages.insertOne(
    {_id: 1, rating: {count: 2, avg: 4}},
    {writeConcern: {w: "majority", wtimeout: 10000}}
  );
'
secondary_ready='db.hello().secondary && db.getSiblingDB("poster_read_preference_demo").runCommand({find: "event_pages", filter: {_id: 1}, readConcern: {level: "majority"}, maxTimeMS: 1000}).cursor.firstBatch.length === 1'
for member in txfault2 txfault3; do
  wait_for "$member" "$secondary_ready"
done

echo "Все узлы доступны. Primary — txfault1."
probe -primary txfault1:27017 txfault2:27017 txfault3:27017

echo "Останавливаем Secondary txfault2."
compose stop txfault2
probe -primary txfault1:27017 -missing-tag txfault3:27017
compose start txfault2
wait_for txfault2 "$secondary_ready"

# Оставляем обе реплики доступными для чтения и откладываем выборы.
for member in txfault2 txfault3; do
  node_eval "$member" 'rs.freeze(180)'
done
echo "Останавливаем Primary txfault1. Выборы временно отложены."
compose stop txfault1
for member in txfault2 txfault3; do
  wait_for "$member" 'db.hello().secondary && !db.hello().primary'
done
probe txfault2:27017 txfault3:27017

for member in txfault2 txfault3; do
  node_eval "$member" 'rs.freeze(0)'
done
wait_for txfault3 'Boolean(db.hello().primary)'
new_primary="$(node_eval txfault3 'print(db.hello().primary)')"
new_secondary=txfault2:27017
if [[ "$new_primary" == "$new_secondary" ]]; then
  new_secondary=txfault3:27017
fi
echo "Избран Primary $new_primary. Прежний Primary по-прежнему выключен."
probe -primary "$new_primary" "$new_secondary"

echo "Все проверки read preference пройдены."
