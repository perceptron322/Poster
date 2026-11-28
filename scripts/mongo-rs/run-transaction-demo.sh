#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCENARIO="${1:-all}"
MONGO_URI="${MONGO_RS_URI:-mongodb://mongo-rs1:27017,mongo-rs2:27017,mongo-rs3:27017/?replicaSet=posterRS}"
CONTAINER="${MONGO_RS_CONTAINER:-poster-mongo-rs1}"
CONTAINER_BINARY="/tmp/poster-mongo-tx-$$"
HOST_BINARY="$(mktemp /tmp/poster-mongo-tx.XXXXXX)"

cleanup() {
  docker exec "$CONTAINER" rm -f "$CONTAINER_BINARY" >/dev/null 2>&1 || true
  rm -f "$HOST_BINARY"
}
trap cleanup EXIT

(
  cd "$ROOT_DIR/cmd/bulk_test"
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o "$HOST_BINARY" .
)

docker cp "$HOST_BINARY" "$CONTAINER:$CONTAINER_BINARY"
docker exec -e MONGO_URI="$MONGO_URI" "$CONTAINER" \
  "$CONTAINER_BINARY" -mode transaction -scenario "$SCENARIO"
