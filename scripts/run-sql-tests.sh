#!/usr/bin/env bash
# Init a throwaway cluster and run tests/sql/*.sql. Extension must already be installed.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PGDATA="${PGDATA:-${TMPDIR:-/tmp}/plecl-pgdata}"
export PGUSER="${PGUSER:-${USER:-postgres}}"
SQL_DIR="${SQL_DIR:-$ROOT/tests/sql}"

is_windows() {
  [[ -n "${MSYSTEM:-}" || "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* \
    || "${OS:-}" == Windows_NT || "$(uname -s 2>/dev/null)" == MINGW* \
    || "$(uname -s 2>/dev/null)" == MSYS* ]]
}

find_pgbin() {
  if command -v initdb >/dev/null 2>&1; then
    dirname "$(command -v initdb)"
    return
  fi
  if command -v pg_config >/dev/null 2>&1; then
    pg_config --bindir
    return
  fi
  local d
  for d in \
    ${PG_MSVC_ROOT:+$PG_MSVC_ROOT/bin} \
    /usr/lib/postgresql/16/bin /usr/lib/postgresql/15/bin \
    /usr/lib/postgresql/17/bin /usr/lib/postgresql/18/bin \
    /opt/homebrew/opt/postgresql@16/bin /usr/local/opt/postgresql@16/bin \
    /mingw64/bin \
    "/c/Program Files/PostgreSQL/16/bin" \
    "/c/Program Files/PostgreSQL/17/bin" \
    "/c/Program Files/PostgreSQL/18/bin"
  do
    if [[ -n "$d" && -x "$d/initdb" ]]; then
      echo "$d"
      return
    fi
  done
  return 1
}

PGBIN=$(find_pgbin) || {
  echo "initdb not found (install PostgreSQL server + put pg_config on PATH)" >&2
  exit 1
}
export PATH="${PGBIN}:${PATH}"
if [[ -z "${ECLDIR:-}" ]] && command -v pg_config >/dev/null 2>&1; then
  _pkglib=$(pg_config --pkglibdir)
  if [[ -d "$_pkglib/encodings" ]]; then
    export ECLDIR="${_pkglib}/"
  fi
fi

mkdir -p "$PGDATA"
rm -rf "$PGDATA"
if is_windows; then
  initdb -D "$PGDATA" --auth-local=trust --auth-host=trust --encoding=UTF8 --locale=C >/dev/null
else
  initdb -D "$PGDATA" --auth-local=trust --auth-host=trust >/dev/null
fi

if is_windows; then
  export PGHOST=127.0.0.1
  export PGPORT="${PGPORT:-55432}"
  {
    echo "listen_addresses = '127.0.0.1'"
    echo "port = ${PGPORT}"
  } >> "$PGDATA/postgresql.conf"
  pg_ctl -D "$PGDATA" -l "${TMPDIR:-/tmp}/plecl-pg.log" -w start
else
  export PGHOST="${PGHOST:-/tmp}"
  {
    echo "unix_socket_directories = '${PGHOST}'"
    echo "listen_addresses = ''"
  } >> "$PGDATA/postgresql.conf"
  pg_ctl -D "$PGDATA" -l "${TMPDIR:-/tmp}/plecl-pg.log" -o "-k ${PGHOST}" -w start
fi
trap 'pg_ctl -D "$PGDATA" -m fast stop >/dev/null 2>&1 || true' EXIT

createdb plecl_test
shopt -s nullglob
for f in "$SQL_DIR"/*.sql; do
  echo "== $(basename "$f") =="
  psql -d plecl_test -v ON_ERROR_STOP=1 -f "$f"
done
echo "plecl extension tests OK"
