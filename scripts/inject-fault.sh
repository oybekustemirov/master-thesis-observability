#!/usr/bin/env bash
# Fault injection. Called by run-experiment.sh at a scheduled offset, or standalone.
#
#   ./scripts/inject-fault.sh F1
#
# Each case is designed to discriminate BETWEEN modes: a fault that hurts every mode equally
# tells the thesis nothing.
set -uo pipefail
cd "$(dirname "$0")/.."

FAULT="${1:?fault kodi kerak (F1|F2|F3|F4|F8|F11)}"
APP_PORT=8095
ora() { docker exec obsv-oracle bash -lc "sqlplus -S -L / as sysdba </dev/null <<'EOSQL'
$1
EOSQL"; }
log() { echo "[fault $(date +%H:%M:%S)] $*"; }

case "$FAULT" in

  F1|F1R) # JVM SIGKILL mid-load.
      # Discriminator: B1 and B2 lose every event that was committed but not yet acknowledged
      # by the broker. AQ, B3, HYBRID and CDC lose nothing, because the event is already
      # durable in the database when the process dies.
      PIDS=$(ss -ltnp 2>/dev/null | grep ":$APP_PORT " | grep -oP 'pid=\K[0-9]+' | sort -u)
      log "SIGKILL ilovaga: $PIDS"
      kill -9 $PIDS 2>/dev/null
      sleep 10
      JAR=$(ls target/*.jar | grep -v sources | head -1)
      MODE=$(grep -oP 'mode=\K[A-Z_0-9]+' results/*/run.log 2>/dev/null | tail -1)
      log "ilova qayta ishga tushirilmoqda (mode=${MODE:-WRAPPER_B3})"
      nohup java -jar "$JAR" --observability.mode="${MODE:-WRAPPER_B3}" \
            > /tmp/app-restart.log 2>&1 & disown
      ;;

  F2) # Kafka majority unavailable for 90s.
      # Discriminator: B1 and B2 lose events outright. AQ and B3 accumulate a backlog inside
      # the database and lose nothing. CDC accumulates inside Kafka Connect.
      log "kafka-2 va kafka-3 to'xtatilmoqda (90s)"
      docker stop obsv-kafka-2 obsv-kafka-3 >/dev/null
      sleep 90
      log "brokerlar qaytarilmoqda"
      docker start obsv-kafka-2 obsv-kafka-3 >/dev/null
      ;;

  F3) # Kafka Connect worker killed for 120s.
      # Discriminator: measures CDC recovery time and the duplicate volume produced by
      # replaying from the last committed offset.
      log "Connect to'xtatilmoqda (120s)"
      docker stop obsv-connect >/dev/null
      sleep 120
      log "Connect qaytarilmoqda"
      docker start obsv-connect >/dev/null
      ;;

  F4|F4R) # Archive logs purged during a Connect outage.
      # THE key negative result for pure CDC: the mined window becomes unrecoverable and the
      # events in it are lost permanently, with no artefact recording that they existed.
      # The first version switched the log twice and deleted the archives, and the connector
      # simply resumed from an SCN still present in the ONLINE logs: three repetitions, zero
      # loss, condition never reproduced. Oracle will not overwrite an online group until it
      # has been archived, so the redo the connector needs only becomes unreachable once
      # enough switches have cycled past every group AND those archives are gone.
      SWITCHES="${2:-10}"
      log "Connect to'xtatilmoqda; $SWITCHES marta log almashtiriladi, so'ng archive'lar o'chiriladi"
      docker stop obsv-connect >/dev/null
      sleep 30
      SW_SQL=""
      for _ in $(seq 1 "$SWITCHES"); do
        SW_SQL="${SW_SQL}ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM ARCHIVE LOG CURRENT;
"
      done
      ora "${SW_SQL}EXIT;" >/dev/null 2>&1
      log "RMAN: barcha archive log'lar o'chirilmoqda"
      docker exec obsv-oracle bash -lc \
        "rman target / <<'EOR' 2>&1 | tail -3
DELETE NOPROMPT ARCHIVELOG ALL;
EXIT;
EOR" || log "rman mavjud emas — o'chirish o'tkazib yuborildi"
      sleep 20
      docker start obsv-connect >/dev/null
      log "Connect qaytarildi — endi ORA-01291 kutilmoqda"
      ;;

  F8) # A trigger that raises.
      # Discriminator: in AQ mode the business transactions FAIL. This is the
      # availability-coupling result: an observability defect stops payments.
      log "AQ triggerini sindirmoqdamiz (PKG_A1_EVENT yaroqsiz qilinadi)"
      ora "ALTER SESSION SET CONTAINER = OBSVPDB;
CREATE OR REPLACE PACKAGE BODY obsv.PKG_A1_EVENT AS
  FUNCTION event_type_for(p_old IN VARCHAR2, p_new IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN RETURN 'broken'; END;
END PKG_A1_EVENT;
/
EXIT;" 2>&1 | tail -2
      log "paket endi yaroqsiz — AQ rejimida DML yiqilishi kerak"
      ;;

  F11B) # The same batch, but writing through the shared EMIT_A1_EVENT contract.
       # F11 measures a legacy writer that was NOT modified; F11B measures one that WAS.
       # Together they test both sides of the hybrid's central assumption instead of only the
       # side that makes it look bad.
      COUNT="${2:-20000}"
      log "$COUNT tranzaksiya batch orqali, LEKIN outbox shartnomasi bilan"
      ora "ALTER SESSION SET CONTAINER = OBSVPDB;
SET SERVEROUTPUT ON
BEGIN obsv.PKG_SYNTH_DATA.generate_transactions(p_count => $COUNT, p_source => 'BATCH_EOD',
                                                p_emit_outbox => TRUE); END;
/
EXIT;" 2>&1 | tail -2
      ;;

  F11) # Direct batch writes that bypass the application entirely.
       # Discriminator: the wrapper produces ZERO events for this workload; CDC and the
       # trigger capture all of it. This turns assumption A-3 from an argument into a number.
      COUNT="${2:-20000}"
      log "$COUNT tranzaksiya ilovadan chetlab yaratilmoqda (PL/SQL batch)"
      ora "ALTER SESSION SET CONTAINER = OBSVPDB;
SET SERVEROUTPUT ON
BEGIN obsv.PKG_SYNTH_DATA.generate_transactions(p_count => $COUNT, p_source => 'BATCH_EOD'); END;
/
EXIT;" 2>&1 | tail -2
      ;;

  F5|F5R) # A transaction left open longer than Debezium's transaction retention.
      # Discriminator: CDC discards the buffered transaction SILENTLY.
      #
      # The hold is in SECONDS and defaults to 240, chosen against two constraints that the
      # earlier 30-minute default satisfied neither of. It must EXCEED the connector's
      # log.mining.transaction.retention.ms (180 s) so the transaction is actually discarded,
      # and the commit must land INSIDE the measured window, or the run ends before the events
      # could have appeared and their absence proves nothing. With --fault-at 30 and a 420 s
      # run: open at t=30, retention expires ~t=210, commit at t=270, run ends at t=420.
      #
      # Tagged with a module name so repair-after-fault.sh can find and kill it. The previous
      # version left a session sleeping for half an hour on 5 000 uncommitted rows, and the
      # next cell's workload reset would block on those locks.
      SECS="${2:-240}"
      log "bitta ochiq tranzaksiyada 5000 satr, $SECS soniya ushlab turiladi"
      ora "ALTER SESSION SET CONTAINER = OBSVPDB;
BEGIN
  DBMS_APPLICATION_INFO.SET_MODULE('F5_LONG_TX', NULL);
  -- p_emit_outbox => TRUE is what makes this a RETENTION test. Without it the batch writes
  -- no outbox rows, so every outbox-based mode reports the events missing for the F11 reason
  -- and the retention path is never exercised at all.
  obsv.PKG_SYNTH_DATA.generate_transactions(p_count => 5000, p_source => 'LONG_TX',
                                            p_commit_every => 0, p_emit_outbox => TRUE);
  DBMS_SESSION.SLEEP($SECS);
  COMMIT;
  DBMS_APPLICATION_INFO.SET_MODULE(NULL, NULL);
END;
/
EXIT;" 2>&1 | tail -2 &
      ;;

  *) echo "noma'lum fault: $FAULT" >&2; exit 2 ;;
esac
log "$FAULT tugadi"
