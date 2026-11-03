#!/bin/sh
set -eu

CONFIG_FILE="$(mktemp /tmp/patroni.XXXXXX.yml)"
trap 'rm -f "$CONFIG_FILE"' EXIT

envsubst < /etc/patroni/patroni.yml.template > "$CONFIG_FILE"
chown postgres:postgres "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

# Новый том наследует от образа права 1777, а pg_basebackup на реплике
# их не исправляет; PostgreSQL требует 0700.
chown postgres:postgres /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data

exec gosu postgres patroni "$CONFIG_FILE"
