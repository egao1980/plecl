#!/usr/bin/env bash
# Load lineitem then the plecl analytics.
#   TPCH_SCALE=1 ./load.sh          # real TPC-H via duckdb (≈1GB)
#   TPCH_ROWS=6000000 ./load.sh     # synth SF1-sized (default 200000)
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
DB=${PGDATABASE:-plecl_tpch}
PSQL=(psql -v ON_ERROR_STOP=1 -d "$DB")

"${PSQL[@]}" -c "CREATE EXTENSION IF NOT EXISTS plecl;"
"${PSQL[@]}" -f "$DIR/schema.sql"

if [[ -n "${TPCH_SCALE:-}" ]] && command -v duckdb >/dev/null; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  echo "duckdb dbgen sf=${TPCH_SCALE} → $TMP"
  duckdb -c "INSTALL tpch; LOAD tpch; CALL dbgen(sf=${TPCH_SCALE});
             COPY lineitem TO '${TMP}/lineitem.csv' (HEADER, DELIMITER '|');"
  "${PSQL[@]}" -c "TRUNCATE lineitem;"
  "${PSQL[@]}" -c "COPY lineitem FROM '${TMP}/lineitem.csv' WITH (FORMAT csv, HEADER true, DELIMITER '|')"
  "${PSQL[@]}" -c "ANALYZE lineitem;"
else
  N=${TPCH_ROWS:-200000}
  echo "synth lineitem n=${N} (set TPCH_SCALE=1 + duckdb for real TPC-H)"
  "${PSQL[@]}" -v n="$N" -f "$DIR/synth.sql"
fi

"${PSQL[@]}" -f "$DIR/analytics.sql"
echo "lineitem + analytics ready on $DB"
