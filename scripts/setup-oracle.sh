#!/usr/bin/env bash
# Idempotent Oracle preparation for the experiment stack.
# Safe to re-run: the ARCHIVELOG step (which restarts the database) is skipped when the
# database is already in ARCHIVELOG mode.
#
# Nested heredocs are avoided deliberately: quoting a $-bearing SQL string through
# `docker exec bash -lc "... <<EOF"` mangles it. SQL is written to a file and copied in.
set -euo pipefail

C=${ORACLE_CONTAINER:-obsv-oracle}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# No -i: an open stdin makes sqlplus block forever waiting for input if a statement
# errors under WHENEVER SQLERROR CONTINUE. </dev/null makes any such prompt an instant EOF.
run_init() { docker exec "$C" bash -lc "sqlplus -S / as sysdba @/opt/obsv/init/$1 </dev/null"; }

run_query() {                      # run_query <name> <sql-file-content-on-stdin>
  cat > "$TMP/$1.sql"
  docker cp "$TMP/$1.sql" "$C:/tmp/$1.sql" >/dev/null
  docker exec "$C" bash -lc "sqlplus -S -L / as sysdba @/tmp/$1.sql </dev/null"
}

echo "==> Oracle tayyorlanmoqda ($C)"

log_mode=$(run_query logmode <<'SQL' | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF
SELECT log_mode FROM v$database;
EXIT;
SQL
)

if [[ "$log_mode" == "ARCHIVELOG" ]]; then
  echo "    [1/3] ARCHIVELOG allaqachon yoqilgan — restart o'tkazib yuborildi"
else
  echo "    [1/3] ARCHIVELOG yoqilmoqda (baza qayta ishga tushadi, ~60s)"
  run_init 01_cdb_logging.sql | tail -5
fi

echo "    [2/3] Debezium capture user"
run_init 02_capture_user.sql | grep -E '^(created|logminer_tbs|c##dbzuser|>>>)' || true

echo "    [3/3] OBSV schema owner"
run_init 03_pdb_schema.sql | grep -E '^(created|>>>)' || true

echo "==> Tekshiruv"
run_query verify <<'SQL'
SET LINESIZE 120 PAGESIZE 50 FEEDBACK OFF VERIFY OFF
COLUMN check_name FORMAT A22
COLUMN value      FORMAT A16
SELECT 'log_mode'         AS check_name, log_mode                  AS value FROM v$database
UNION ALL SELECT 'force_logging',        force_logging                     FROM v$database
UNION ALL SELECT 'supplemental_min',     supplemental_log_data_min         FROM v$database
UNION ALL SELECT 'archive_dest_status',  status                            FROM v$archive_dest_status WHERE dest_id = 1
UNION ALL SELECT 'capture_user',   NVL(MAX(username),'** MISSING **') FROM dba_users WHERE username = 'C##DBZUSER'
UNION ALL SELECT 'app_schema',     NVL(MAX(username),'** MISSING **') FROM cdb_users WHERE username = 'OBSV';
EXIT;
SQL
