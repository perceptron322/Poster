
#!/bin/bash
set -Eeuo pipefail

PGDATA="${PGDATA:-/var/lib/postgresql/data}"
TLS_DIR="/var/lib/postgresql/tls"
PASSFILE="/var/lib/postgresql/.pgpass"

: "${REPLICATOR_PASSWORD:?REPLICATOR_PASSWORD is required}"

mkdir -p "$PGDATA" "$TLS_DIR"
chown postgres:postgres "$PGDATA" "$TLS_DIR"

# Create a TLS certificate dedicated to the replica.
if [ ! -s "$TLS_DIR/server.crt" ] || [ ! -s "$TLS_DIR/server.key" ]; then
    openssl req -new -x509 -days 365 -nodes \
        -keyout "$TLS_DIR/server.key" \
        -out "$TLS_DIR/server.crt" \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
fi

chown postgres:postgres "$TLS_DIR/server.crt" "$TLS_DIR/server.key"
chmod 644 "$TLS_DIR/server.crt"
chmod 600 "$TLS_DIR/server.key"

# Configure password lookup for streaming replication.
# Passwords containing ':' or '\' need escaping in a .pgpass file.
printf 'db:5432:replication:replicator:%s\n' "$REPLICATOR_PASSWORD" > "$PASSFILE"
chown postgres:postgres "$PASSFILE"
chmod 600 "$PASSFILE"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Initializing standby from primary..."

    until gosu postgres pg_basebackup \
        --dbname="host=db port=5432 user=replicator dbname=replication sslmode=require passfile=$PASSFILE" \
        --pgdata="$PGDATA" \
        --format=plain \
        --wal-method=stream \
        --progress \
        --write-recovery-conf \
        --slot=poster_replica_slot \
        --create-slot
    do
        echo "Base backup failed; retrying in 5 seconds..."
        sleep 5
    done
fi

exec gosu postgres postgres \
    -D "$PGDATA" \
    -c ssl=on \
    -c ssl_cert_file="$TLS_DIR/server.crt" \
    -c ssl_key_file="$TLS_DIR/server.key" \
    -c hba_file=/etc/postgresql/pg_hba.conf
