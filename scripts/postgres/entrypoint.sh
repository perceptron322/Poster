#!/bin/sh
set -eu

sh /scripts/generate-certs.sh

exec docker-entrypoint.sh "$@"
