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

PG_BIN=
for pg_bin_candidate in /opt/homebrew/opt/postgresql@18/bin /usr/lib/postgresql/18/bin; do
  if [[ -d "$pg_bin_candidate" ]]; then
    PG_BIN="$pg_bin_candidate"
    break
  fi
done

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

database_ready() {
  if [[ -n "$PG_BIN" ]]; then
    "$PG_BIN/pg_isready" -h "$POSTGRES_HOST" -p "$PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1
  else
    "$RUNTIME" exec "$NAME" pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1
  fi
}

ready=false
for _ in $(seq 1 120); do
  if database_ready; then
    ready=true
    break
  fi
  sleep 1
done

if [[ "$ready" != true ]]; then
  echo "PostgreSQL did not accept TCP connections within 120 seconds." >&2
  if [[ -n "$PG_BIN" ]]; then
    cat "$WORK/pg.log" >&2
  else
    "$RUNTIME" logs "$NAME" >&2
  fi
  exit 1
fi

swift test --parallel "$@"
