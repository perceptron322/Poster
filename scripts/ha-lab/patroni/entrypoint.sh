#!/bin/sh
set -eu

CONFIG_FILE="$(mktemp /tmp/patroni.XXXXXX.yml)"
trap 'rm -f "$CONFIG_FILE"' EXIT

envsubst < /etc/patroni/patroni.yml.template > "$CONFIG_FILE"
chown postgres:postgres "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

exec gosu postgres patroni "$CONFIG_FILE"
