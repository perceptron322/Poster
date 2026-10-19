#!/bin/sh
set -eu

CERT_DIR="/var/lib/postgresql/data"

if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -f "$CERT_DIR/server.key" ]; then
    echo "Generating self-signed PostgreSQL TLS certificate..."

    openssl req -new -x509 -days 365 -nodes \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
fi

chown postgres:postgres "$CERT_DIR/server.crt" "$CERT_DIR/server.key"
chmod 644 "$CERT_DIR/server.crt"
chmod 600 "$CERT_DIR/server.key"
