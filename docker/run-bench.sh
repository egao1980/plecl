#!/usr/bin/env bash
set -euo pipefail

export PGDATA="${PGDATA:-/tmp/pgdata-bench}"
export PGUSER="${PGUSER:-postgres}"
export PGHOST=/tmp

PGBIN=""
for d in /usr/lib/postgresql/16/bin /usr/lib/postgresql/15/bin /usr/lib/postgresql/17/bin /usr/lib/postgresql/18/bin; do
  if [[ -x "$d/initdb" ]]; then
    PGBIN=$d
    break
  fi
done
if [[ -z "$PGBIN" ]]; then
  echo "initdb not found" >&2
  exit 1
fi
export PATH="${PGBIN}:${PATH}"

mkdir -p "$PGDATA" /tmp
chown -R postgres:postgres "$PGDATA" /tmp || true

if [[ ! -f "$PGDATA/PG_VERSION" ]]; then
  su -s /bin/bash postgres -c "${PGBIN}/initdb -D '$PGDATA' --auth-local=trust --auth-host=trust"
fi

echo "unix_socket_directories = '/tmp'" >> "$PGDATA/postgresql.conf"
echo "listen_addresses = ''" >> "$PGDATA/postgresql.conf"

su -s /bin/bash postgres -c "${PGBIN}/pg_ctl -D '$PGDATA' -l /tmp/pg-bench.log -o '-k /tmp' -w start"
trap 'su -s /bin/bash postgres -c "${PGBIN}/pg_ctl -D \"$PGDATA\" -m fast stop" || true' EXIT

su -s /bin/bash postgres -c "${PGBIN}/createdb -h /tmp plecl_bench" || true
echo "=== plecl bench ==="
su -s /bin/bash postgres -c "${PGBIN}/psql -h /tmp -d plecl_bench -v ON_ERROR_STOP=1 -f /src/bench/bench.sql"
echo "=== bench done ==="
