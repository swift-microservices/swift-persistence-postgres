#!/bin/bash
# Runs the test suite against an ephemeral Postgres.
#
# Uses a Homebrew PostgreSQL 18 if one is installed, otherwise a `postgres:18` container through
# `docker` or `container`. If POSTGRES_HOST is already set, uses that database and starts nothing.
set -euo pipefail

if [[ -n "${POSTGRES_HOST:-}" ]]; then
  exec swift test --parallel "$@"
fi

PORT=${POSTGRES_PORT:-5498}
export POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=$PORT POSTGRES_USER=postgres POSTGRES_PASSWORD=postgres POSTGRES_DB=postgres

PG_BIN=$(ls -d /opt/homebrew/opt/postgresql@18/bin /usr/lib/postgresql/18/bin 2>/dev/null | head -1 || true)

if [[ -n "$PG_BIN" ]]; then
  WORK=$(mktemp -d)
  trap '"$PG_BIN/pg_ctl" -D "$WORK/pg" stop -m immediate >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
  "$PG_BIN/initdb" -D "$WORK/pg" -U postgres -A trust >/dev/null
  "$PG_BIN/pg_ctl" -D "$WORK/pg" -o "-p $PORT -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" -l "$WORK/pg.log" start >/dev/null
else
  RUNTIME=$(command -v docker || command -v container || true)
  [[ -n "$RUNTIME" ]] || { echo "No PostgreSQL 18 found: install postgresql@18 or docker." >&2; exit 1; }
  NAME=swift-persistence-postgres-test-$$
  trap '"$RUNTIME" rm -f "$NAME" >/dev/null 2>&1 || true' EXIT
  "$RUNTIME" run -d --name "$NAME" -e POSTGRES_PASSWORD=postgres -p "$PORT:5432" postgres:18 >/dev/null
fi

for _ in $(seq 1 60); do
  (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && break
  sleep 0.5
done

swift test --parallel "$@"
