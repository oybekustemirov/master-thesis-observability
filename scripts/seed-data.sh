#!/usr/bin/env bash
# Generates the synthetic dataset. Deterministic: the same seed always yields the same data,
# which is what makes the experiments reproducible by a third party.
#
#   ./scripts/seed-data.sh                      50 000 customers, no transactions
#   ./scripts/seed-data.sh --customers 10000    smaller reference population
#   ./scripts/seed-data.sh --transactions 5000  also generate a batch workload
#   ./scripts/seed-data.sh --reset              clear workload, keep reference data
#   ./scripts/seed-data.sh --purge              clear EVERYTHING and regenerate
set -euo pipefail

C=${ORACLE_CONTAINER:-obsv-oracle}
CUSTOMERS=50000
TRANSACTIONS=0
SEED=20260902
RESET=0
PURGE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --customers)    CUSTOMERS="$2"; shift 2 ;;
    --transactions) TRANSACTIONS="$2"; shift 2 ;;
    --seed)         SEED="$2"; shift 2 ;;
    --reset)        RESET=1; shift ;;
    --purge)        PURGE=1; shift ;;
    *) echo "noma'lum argument: $1" >&2; exit 2 ;;
  esac
done

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SQL="$TMP/seed.sql"

{
  echo "SET LINESIZE 150 PAGESIZE 80 FEEDBACK OFF VERIFY OFF TIMING ON"
  echo "WHENEVER SQLERROR EXIT 1"
  echo "ALTER SESSION SET CONTAINER = OBSVPDB;"
  echo "SET SERVEROUTPUT ON SIZE UNLIMITED"

  if [[ $PURGE -eq 1 ]]; then
    echo "PROMPT == purge: hamma narsa o'chirilmoqda =="
    echo "BEGIN obsv.PKG_SYNTH_DATA.reset_workload; END;"
    echo "/"
    echo "DELETE FROM obsv.ACCOUNT;"
    echo "DELETE FROM obsv.CUSTOMER;"
    echo "DELETE FROM obsv.SYNTH_CONFIG;"
    echo "COMMIT;"
  elif [[ $RESET -eq 1 ]]; then
    echo "PROMPT == reset: workload o'chirilmoqda, reference saqlanadi =="
    echo "BEGIN obsv.PKG_SYNTH_DATA.reset_workload; END;"
    echo "/"
  fi

  if [[ $RESET -eq 0 ]]; then
    echo "PROMPT == reference: $CUSTOMERS mijoz (seed $SEED) =="
    echo "BEGIN obsv.PKG_SYNTH_DATA.generate_reference(p_customers => $CUSTOMERS, p_seed => $SEED); END;"
    echo "/"
  fi

  if [[ "$TRANSACTIONS" -gt 0 ]]; then
    echo "PROMPT == workload: $TRANSACTIONS tranzaksiya (BATCH_EOD, ilovadan chetlab) =="
    echo "BEGIN obsv.PKG_SYNTH_DATA.generate_transactions(p_count => $TRANSACTIONS, p_source => 'BATCH_EOD'); END;"
    echo "/"
  fi

  echo "SET TIMING OFF"
  echo "PROMPT == holat =="
  cat <<'EOSQL'
SELECT (SELECT COUNT(*) FROM obsv.CUSTOMER)     AS customers,
       (SELECT COUNT(*) FROM obsv.ACCOUNT)      AS accounts,
       (SELECT COUNT(*) FROM obsv.TXN_A1)       AS transactions,
       (SELECT COUNT(*) FROM obsv.LEDGER_ENTRY) AS ledger_rows,
       (SELECT COUNT(*) FROM obsv.GROUND_TRUTH) AS ground_truth
  FROM dual;
EXIT;
EOSQL
} > "$SQL"

docker cp "$SQL" "$C:/tmp/seed.sql" >/dev/null
docker exec "$C" bash -lc "sqlplus -S -L / as sysdba @/tmp/seed.sql </dev/null"
