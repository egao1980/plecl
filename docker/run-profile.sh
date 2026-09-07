#!/usr/bin/env bash
# Profile the TPC-H Lisp UDFs. TPCH_ROWS=6000000 ≈ SF1 / 1GB.
set -euo pipefail

export PGDATA="${PGDATA:-/tmp/pgdata-profile}"
export PGUSER="${PGUSER:-postgres}"
export PGHOST=/tmp
export PGDATABASE=plecl_tpch
N=${TPCH_ROWS:-200000}

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
echo "work_mem = '64MB'" >> "$PGDATA/postgresql.conf"

su -s /bin/bash postgres -c "${PGBIN}/pg_ctl -D '$PGDATA' -l /tmp/pg-profile.log -o '-k /tmp' -w start"
trap 'su -s /bin/bash postgres -c "${PGBIN}/pg_ctl -D \"$PGDATA\" -m fast stop" || true' EXIT

su -s /bin/bash postgres -c "${PGBIN}/createdb -h /tmp plecl_tpch" || true
echo "=== plecl tpch profile n=${N} ==="
su -s /bin/bash postgres -c "export TPCH_ROWS=$N PGDATABASE=plecl_tpch PGHOST=/tmp
  /src/examples/tpch/load.sh"
su -s /bin/bash postgres -c "${PGBIN}/psql -h /tmp -d plecl_tpch -v ON_ERROR_STOP=1 -f /src/examples/tpch/profile.sql"
echo "=== profile done ==="
