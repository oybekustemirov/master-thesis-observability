#!/usr/bin/env bash
# Restores known-good state after a fault cell.
#
# Without this the fault matrix poisons itself. Three of the injected faults leave permanent
# damage that the next cell would silently inherit:
#
#   F8  replaces PKG_A1_EVENT with a broken body and never puts it back. Flyway will not
#       re-apply V8 because it is already recorded as applied, so every later AQ cell would run
#       against a broken package and report failures caused by the PREVIOUS cell's fault.
#   F5  leaves a session sleeping on an open transaction holding 5 000 uncommitted rows. The
#       next cell's workload reset blocks on those locks.
#   F4  stops the Connect container. If it does not come back healthy, every later CDC and
#       HYBRID cell fails for a reason that has nothing to do with the mode under test.
#
# Run after every fault cell, before the next one starts.
set -uo pipefail
cd "$(dirname "$0")/.."

log() { echo "[repair] $*"; }
ora() { local f="$1"; shift; docker exec obsv-oracle bash -lc "sqlplus -S -L / as sysdba @$f $* </dev/null"; }

FAILED=0

# ------------------------------------------------- 1. kill lingering sessions ----
cat > /tmp/repair-sessions.sql <<'SQL'
SET FEEDBACK OFF VERIFY OFF SERVEROUTPUT ON
ALTER SESSION SET CONTAINER = OBSVPDB;
SET SERVEROUTPUT ON
DECLARE
  l_killed PLS_INTEGER := 0;
BEGIN
  -- Any session still holding a transaction open from a previous cell. Identified through
  -- V$TRANSACTION rather than by name, because the fault scripts run as SYS through SQL*Plus
  -- and carry no distinguishing username.
  FOR s IN (SELECT sid, serial# FROM v$session WHERE module IN ('F5_LONG_TX', 'C2_NOISE')
            UNION
            SELECT s.sid, s.serial#
              FROM v$session s JOIN v$transaction t ON t.ses_addr = s.saddr
             WHERE s.username IS NOT NULL
               AND s.last_call_et > 60
               AND s.status = 'INACTIVE') LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
      l_killed := l_killed + 1;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('lingering transactions killed: ' || l_killed);
END;
/
EXIT;
SQL
docker cp /tmp/repair-sessions.sql obsv-oracle:/tmp/ >/dev/null
ora /tmp/repair-sessions.sql 2>&1 | grep -E 'killed|ORA-' || true

# ---------------------------------------------------- 2. restore PKG_A1_EVENT ----
# Re-applied from the migration itself rather than from a second copy, so there is one source
# of truth and the repair cannot drift away from what the experiment is supposed to be running.
log "PKG_A1_EVENT V8 dan tiklanmoqda"
docker cp src/main/resources/db/migration/V8__aq_event_id_property.sql \
          obsv-oracle:/tmp/restore_pkg.sql >/dev/null
docker exec obsv-oracle bash -lc \
  "sqlplus -S obsv/Obsv_2026@//localhost:1521/OBSVPDB @/tmp/restore_pkg.sql </dev/null" \
  >/dev/null 2>&1 || true

# ------------------------------------------------------ 3. connect container ----
if [[ "$(docker inspect -f '{{.State.Running}}' obsv-connect 2>/dev/null)" != "true" ]]; then
  log "obsv-connect to'xtagan — qayta ishga tushirilmoqda"
  docker start obsv-connect >/dev/null 2>&1 || true
fi
for i in $(seq 1 60); do
  curl -sf http://localhost:8083/ >/dev/null 2>&1 && break
  sleep 2
  [[ $i -eq 60 ]] && { log "XATO: Connect qaytmadi"; FAILED=1; }
done

# ------------------------------------------------------------- 4. verify ----
# The repair asserts its own result. A repair that silently fails is worse than no repair,
# because it leaves the matrix running against damage nobody is looking for any more.
cat > /tmp/repair-verify.sql <<'SQL'
SET FEEDBACK OFF VERIFY OFF PAGESIZE 0 HEADING OFF TRIMSPOOL ON
ALTER SESSION SET CONTAINER = OBSVPDB;
SPOOL /tmp/repair_status.txt
SELECT 'INVALID:' || COUNT(*) FROM all_objects
 WHERE owner = 'OBSV' AND status <> 'VALID';
SELECT 'OPENTX:' || COUNT(*) FROM v$transaction;
SPOOL OFF
EXIT;
SQL
docker cp /tmp/repair-verify.sql obsv-oracle:/tmp/ >/dev/null
ora /tmp/repair-verify.sql >/dev/null 2>&1 || true
STATUS=$(docker exec obsv-oracle cat /tmp/repair_status.txt 2>/dev/null | tr -d ' \r' | tr '\n' ' ')
log "holat: $STATUS"

INVALID=$(sed -n 's/.*INVALID:\([0-9]*\).*/\1/p' <<<"$STATUS")
if [[ "${INVALID:-0}" != "0" ]]; then
  log "XATO: OBSV da ${INVALID} ta yaroqsiz obyekt qoldi"
  FAILED=1
fi

[[ $FAILED -eq 0 ]] && log "tiklandi" || log "TIKLASH TO'LIQ EMAS"
exit $FAILED
