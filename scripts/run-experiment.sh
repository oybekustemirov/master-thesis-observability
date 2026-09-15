#!/usr/bin/env bash
# One command = one experiment cell (mode x profile x repetition), fully archived.
#
#   ./scripts/run-experiment.sh --mode WRAPPER_B3 --profile P1 --rep 1
#   ./scripts/run-experiment.sh --mode WRAPPER_B1 --profile P1 --rep 1 --fault F1
#   ./scripts/run-experiment.sh --mode CDC --profile P1 --tps 300 --duration 3m
#
# Every artefact of a run lands under results/<run-id>/ so a result in the thesis can be
# traced back to the raw data that produced it.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=WRAPPER_B3; PROFILE=P1; REP=1; TPS=200; DURATION=3m; FAULT=none; FAULT_AT=60
WORKLOAD_PROFILE=
NO_CONNECTOR=0
FIXED_SETTLE=
SETTLE_MAX=120; APP_PORT=8095
TOPIC=bank.a1.transaction.events

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    # The label recorded in summary.csv and the k6 scenario are different things. C2 labels its
    # cells C2N0OFF..C2WIDE so they never pool with P1 rows, while still driving the P1 workload.
    --workload-profile) WORKLOAD_PROFILE="$2"; shift 2 ;;
    --rep) REP="$2"; shift 2 ;;
    --tps) TPS="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --fault) FAULT="$2"; shift 2 ;;
    --fault-at) FAULT_AT="$2"; shift 2 ;;
    # Experiment C2 needs a CDC-configured run with the connector ABSENT, so that the
    # instance-wide CPU counter can be differenced against the same run with it present.
    # The capture configuration — including supplemental logging — stays on, because it
    # changes how much redo Oracle WRITES and must therefore be identical in both arms.
    --no-connector) NO_CONNECTOR=1; shift ;;
    # Experiment C2 differences two arms of the same workload, so the MEASURED WINDOW must be
    # identical in both. With a variable drain it was not: the connector-absent arm has no sink
    # to fill, never satisfied the non-empty condition, and so always ran the settle to its full
    # timeout while the connector arm drained in seconds. The noise generator kept writing
    # through that extra ~100 s, leaving the two arms 36-40 % apart in total redo and inflating
    # the baseline CPU that gets subtracted.
    --fixed-settle) FIXED_SETTLE="$2"; shift 2 ;;
    *) echo "noma'lum argument: $1" >&2; exit 2 ;;
  esac
done

RUN_ID="${MODE}-${PROFILE}-r${REP}$([ "$FAULT" != none ] && echo "-$FAULT" || true)-$(date +%Y%m%d%H%M%S)"
OUT="results/$RUN_ID"; mkdir -p "$OUT"
JAR=$(ls target/*.jar 2>/dev/null | grep -v sources | head -1 || true)

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/run.log"; }
# Extra arguments are forwarded to SQL*Plus as script parameters (&1, &2, ...). Without this
# a parameterised script blocks on "Enter value for 1" and its output becomes an SP2-0546
# message that the caller then parses as if it were data.
ora() { local f="$1"; shift; docker exec obsv-oracle bash -lc "sqlplus -S -L / as sysdba @$f $* </dev/null"; }

log "=== RUN $RUN_ID ==="
log "mode=$MODE profile=$PROFILE rep=$REP tps=$TPS duration=$DURATION fault=$FAULT"

# ---------------------------------------------------------------- 1. build ----
if [[ -z "$JAR" ]]; then
  log "jar qurilmoqda (bir marta)"
  ./mvnw -q package -DskipTests >> "$OUT/run.log" 2>&1
  JAR=$(ls target/*.jar | grep -v sources | head -1)
fi
log "jar: $JAR"

# ------------------------------------------------------- 2. stop previous ----
PIDS=$(ss -ltnp 2>/dev/null | grep ":$APP_PORT " | grep -oP 'pid=\K[0-9]+' | sort -u || true)
[[ -n "$PIDS" ]] && { log "oldingi ilova to'xtatilmoqda: $PIDS"; kill $PIDS 2>/dev/null || true; sleep 5; }

# ------------------------------------------------------------ 3. reset db ----
# Archived redo accumulates in $ORACLE_HOME/dbs, inside the container's writable layer, and
# nothing ever removed it: 200 runs produced 6 413 archives totalling 61 GB, which filled the
# host disk and killed two experiment chains with I/O errors mid-run. There is no backup
# strategy and no standby here, and every connector starts from the current SCN, so no run ever
# needs an archive written by a previous one. Purging per run bounds the growth to one run.
log "arxiv redo tozalanmoqda"
docker exec obsv-oracle bash -lc 'rm -f $ORACLE_HOME/dbs/arch1_*.dbf' >/dev/null 2>&1 || true

log "workload tozalanmoqda (reference saqlanadi)"
docker cp harness/sql/reset-workload.sql obsv-oracle:/tmp/ >/dev/null
ora /tmp/reset-workload.sql >> "$OUT/run.log" 2>&1 \
  || { log "XATO: reset-workload muvaffaqiyatsiz - run to.xtatildi"; exit 1; }

# --------------------------------------------------------- 4. reset topic ----
# A fresh topic per run keeps reconciliation unambiguous: everything on it belongs to
# this run, so a stale message cannot be counted as a duplicate or a phantom.
log "Kafka topigi qayta yaratilmoqda"
docker exec obsv-kafka-1 /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --delete --topic "$TOPIC" >/dev/null 2>&1 || true
sleep 6
docker exec obsv-kafka-1 /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic "$TOPIC" --partitions 6 --replication-factor 3 \
  --config min.insync.replicas=2 >/dev/null 2>&1 || true

# -------------------------------------------------------------- 5. app up ----
log "ilova ishga tushirilmoqda (mode=$MODE)"
nohup java -jar "$JAR" --observability.mode="$MODE" > "$OUT/app.log" 2>&1 &
APP_PID=$!
disown || true
for i in $(seq 1 60); do
  curl -sf "localhost:$APP_PORT/actuator/health" >/dev/null 2>&1 && break
  sleep 2
  [[ $i -eq 60 ]] && { log "XATO: ilova ko'tarilmadi"; exit 1; }
done
log "ilova tayyor (pid $APP_PID)"

# ------------------------------------------------------ 5b. connector up ----
# Registered AFTER the application has started but BEFORE any workload runs.
#
# After, because ModeActivator switches ALL-column supplemental logging on at startup and that
# is DDL on a captured table; issuing it while the connector is already streaming would put a
# schema change into the middle of the stream for no reason. Before the workload, because the
# connector's starting SCN must precede the first business transaction of the run. Non-Debezium modes explicitly drop every connector: a
# connector left running from a previous cell would keep mining and keep publishing onto the
# topic, and its events would be reconciled as though the mode under test had produced them.
PREFIX="obsv_$(echo "$RUN_ID" | tr 'A-Z.-' 'a-z__')"
case "$MODE" in
  CDC|HYBRID)
    if [[ "$NO_CONNECTOR" == 1 ]]; then
      log "--no-connector: konnektorsiz ishlatilmoqda (C2 bazaviy sharti)"
      ./scripts/register-connector.sh none >> "$OUT/run.log" 2>&1 || true
    else
      log "Debezium konnektori ro'yxatdan o'tkazilmoqda ($MODE, prefix=$PREFIX)"
      ./scripts/register-connector.sh "$MODE" "$PREFIX" >> "$OUT/run.log" 2>&1 \
        || { log "XATO: konnektor ishga tushmadi - run to'xtatildi"; exit 1; }
    fi
    ;;
  *)
    ./scripts/register-connector.sh none >> "$OUT/run.log" 2>&1 || true
    ;;
esac


# ----------------------------------------------------- 6. snapshot before ----
docker cp harness/sql/snapshot-stats.sql obsv-oracle:/tmp/ >/dev/null
ora /tmp/snapshot-stats.sql > /dev/null 2>&1
docker cp obsv-oracle:/tmp/db_stats.csv "$OUT/db_stats_before.csv" >/dev/null

# ------------------------------------------------------------ 7. workload ----
if [[ "$FAULT" != none ]]; then
  log "fault $FAULT ${FAULT_AT}s dan keyin yuboriladi"
  ( sleep "$FAULT_AT"; ./scripts/inject-fault.sh "$FAULT" >> "$OUT/run.log" 2>&1 ) &
fi

log "k6 yuklamasi boshlandi"
RUN_ID="$RUN_ID" PROFILE="${WORKLOAD_PROFILE:-$PROFILE}" TPS="$TPS" DURATION="$DURATION" \
  k6 run --summary-export "$OUT/k6-summary.json" harness/k6/a1-workload.js \
  > "$OUT/k6.log" 2>&1 || log "k6 nolga teng bo'lmagan kod bilan tugadi (natija baribir tahlil qilinadi)"

# --------------------------------------------------- 7a. did the load run? ----
# k6 exits non-zero for threshold breaches too, so its exit code cannot distinguish "some
# requests failed" from "the scenario never started". The iteration count can. A cell with no
# iterations produced no data and must fail loudly rather than be written to summary.csv as a
# row of zeroes.
ITERS=$(python3 -c "
import json,sys
try:
    d=json.load(open('$OUT/k6-summary.json'))
    print(int(d.get('metrics',{}).get('iterations',{}).get('count',0)))
except Exception:
    print(0)
" 2>/dev/null || echo 0)
if [[ "${ITERS:-0}" -eq 0 ]]; then
  log "XATO: k6 bitta ham iteratsiya bajarmadi - katak bekor"
  grep -iE 'level=error' "$OUT/k6.log" 2>/dev/null | head -3 | tee -a "$OUT/run.log"
  exit 1
fi
log "k6 iteratsiyalari: $ITERS"

# ------------------------------------------------------------- 7b. revive ----
# If the application is gone — which is the whole point of fault F1 — bring it back before
# measuring, and let its relay drain what it already committed.
#
# Without this the run exports the topic while the deliverer is dead, and every outbox row
# that was committed but not yet published is counted as a LOST event. Measured effect on the
# first fault matrix: WRAPPER_B3 reported 15/12/14 "missing" against WRAPPER_B1's 0/2/1,
# making the transactional outbox look an order of magnitude worse than the dual write it
# exists to replace. Those events were durable the whole time — the process that would have
# published them had been killed. Distinguishing "lost" from "not yet delivered because the
# deliverer is dead" is the entire point of the pattern, so the measurement has to make it.
#
# Recorded in the run log either way, because a revived run is not identical to one that never
# died and the results chapter must be able to tell them apart.
if ! ss -ltn 2>/dev/null | grep -q ":$APP_PORT "; then
  log "ilova ishlamayapti (fault=$FAULT) — drenaj uchun qayta ishga tushirilmoqda"
  nohup java -jar "$JAR" --observability.mode="$MODE" >> "$OUT/app-revived.log" 2>&1 &
  APP_PID=$!
  disown || true
  REVIVED=no
  for i in $(seq 1 45); do
    if curl -sf "localhost:$APP_PORT/actuator/health" >/dev/null 2>&1; then
      log "ilova qayta tiklandi (${i}x2s)"; REVIVED=yes; break
    fi
    sleep 2
  done
  [[ "$REVIVED" == yes ]] || log "OGOHLANTIRISH: ilova qayta ko'tarilmadi - backlog drenaj qilinmaydi"
  echo "revived=$REVIVED" >> "$OUT/run.meta"
else
  echo "revived=not_needed" >> "$OUT/run.meta"
fi

# -------------------------------------------------------------- 8. settle ----
# Wait for the pipeline to drain rather than using a fixed sleep: a fixed sleep either
# wastes time or truncates a slow pipeline, and truncation would be scored as event loss.
#
# The backlog is read from the DATABASE, not from the application's own metrics. The earlier
# version watched obsv_outbox_pending, a meter that only exists in outbox modes; in AQ and CDC
# runs it read zero on the first attempt and the loop degenerated into the fixed sleep below.
# pending-count.sql sums every in-database mechanism, so the condition means the same thing in
# every mode.
#
# Two independent conditions, because neither alone is sufficient:
#   * in-database backlog is zero  — proves the source side has handed everything over, but is
#     meaningless for the Debezium modes, which never mark anything published;
#   * the topic has stopped growing — proves the sink side has caught up, and means the same
#     thing in every mode, but on its own cannot distinguish "finished" from "stalled".
# Requiring both, and reporting loudly when they are not both met, is what keeps a slow
# pipeline from being exported half-drained and scored as event loss.
# With --fixed-settle the counters are snapshotted after a FIXED wait, identical in every arm,
# and the variable drain runs afterwards purely so the export is complete. Measurement window
# and drain wait are then two different things, which is what they always should have been.
if [[ -n "$FIXED_SETTLE" ]]; then
  log "qat'iy settle: ${FIXED_SETTLE}s (o'lchov oynasi ikkala qo'lda bir xil)"
  sleep "$FIXED_SETTLE"
  ora /tmp/snapshot-stats.sql > /dev/null 2>&1
  docker cp obsv-oracle:/tmp/db_stats.csv "$OUT/db_stats_after.csv" >/dev/null
  FIXED_SNAPSHOT_TAKEN=1
fi

log "pipeline bo'shashi kutilmoqda (maks ${SETTLE_MAX}s)"
docker cp harness/sql/pending-count.sql obsv-oracle:/tmp/ >/dev/null

topic_end_offsets() {
  docker exec obsv-kafka-1 /opt/kafka/bin/kafka-get-offsets.sh \
      --bootstrap-server localhost:9092 --topic "$TOPIC" 2>/dev/null \
    | awk -F: '{s+=$3} END {print s+0}'
}

DRAINED=no
STABLE=0
LAST=-1
# A sink sitting at ZERO is "stable" by any naive reading, and for a Debezium mode the
# in-database backlog is always zero as well — so both conditions were satisfiable before the
# pipeline had produced a single message. Under the heavy uncaptured-redo load of experiment C2
# that is exactly what happened: LogMiner was still behind, the loop declared the pipeline
# drained after four seconds, and the run exported an empty topic and scored 9 003 events as
# lost. Drain therefore requires the sink to be NON-EMPTY and a minimum settle time to have
# passed; a pipeline that genuinely produced nothing now times out and says so, which is the
# correct outcome for a run that failed.
MIN_SETTLE=${MIN_SETTLE:-15}
# SETTLE_MAX is SECONDS, and it was being spent as ITERATIONS. Each pass costs about 2.9 s —
# a docker cp, a SQL*Plus session and a kafka-get-offsets call — so a "120 s" timeout actually
# ran for 344 s. Measured on a real run: settle began at 13:17:05 and gave up at 13:22:49.
# Deadline in wall clock, and poll every few seconds rather than as fast as the calls return:
# the backlog does not change meaningfully in one second, so the extra polling bought nothing.
SETTLE_DEADLINE=$(( $(date +%s) + SETTLE_MAX ))
SETTLE_POLL=${SETTLE_POLL:-3}
i=0
while [[ $(date +%s) -lt $SETTLE_DEADLINE ]]; do
  i=$(( i + SETTLE_POLL ))
  ora /tmp/pending-count.sql "$MODE" >/dev/null 2>&1 || true
  READ=$(docker exec obsv-oracle cat /tmp/pending.txt 2>/dev/null | tr -d '\r' | tr -s ' ' || echo "")
  PENDING=$(awk '{print $1}' <<<"$READ")
  COMMITTED=$(awk '{print $2}' <<<"$READ")
  NOW=$(topic_end_offsets)
  if [[ "$NOW" == "$LAST" ]]; then STABLE=$((STABLE + 1)); else STABLE=0; fi
  LAST="$NOW"
  # Three consecutive identical readings, i.e. two full seconds with nothing published.
  # A connector-absent run has no sink to fill, so requiring a non-empty topic would make it
  # wait the full timeout every time — which is exactly what skewed experiment C2's two arms.
  SINK_OK=1
  if [[ "$NO_CONNECTOR" == 0 && "$MODE" != OFF && "$MODE" != BASELINE_GT ]]; then
    # Completeness, not stillness: every pipeline mode publishes one message per committed
    # transition, so the sink is drained when it has caught up with GROUND_TRUTH. Stillness is
    # kept only as a fallback for a pipeline that has genuinely lost events and will never
    # reach the target — there the timeout is the correct outcome, and it still reports.
    SINK_OK=0
    if [[ -n "${COMMITTED:-}" && "${COMMITTED:-0}" -gt 0 ]]; then
      [[ $(( NOW * 100 )) -ge $(( COMMITTED * 99 )) ]] && SINK_OK=1
    fi
    # 30 s of a completely static sink also counts, so a lossy run is not held to the timeout.
    [[ $STABLE -ge 10 && "${NOW:-0}" -gt 0 ]] && SINK_OK=1
  fi
  if [[ "$PENDING" == "0" && $STABLE -ge 3 && $SINK_OK -eq 1 && $i -ge $MIN_SETTLE ]]; then
    log "pipeline bo'sh (${i}s, sink=$NOW / gt=${COMMITTED:-?})"; DRAINED=yes; break
  fi
  sleep "$SETTLE_POLL"
done
# A run that never drained is reported, not silently analysed: the events still sitting in the
# database would otherwise be counted as lost.
[[ "$DRAINED" == yes ]] || log "OGOHLANTIRISH: pipeline ${SETTLE_MAX}s ichida bo'shamadi (db_pending=$PENDING sink=$LAST gt=${COMMITTED:-?}) - LOSS raqamlari ishonchsiz"
sleep 10   # allow in-flight broker acknowledgements and CDC mining to land

# ------------------------------------------------------ 9. snapshot after ----
if [[ -z "${FIXED_SNAPSHOT_TAKEN:-}" ]]; then
  ora /tmp/snapshot-stats.sql > /dev/null 2>&1
  docker cp obsv-oracle:/tmp/db_stats.csv "$OUT/db_stats_after.csv" >/dev/null
fi

# ---------------------------------------------------------- 10. dump data ----
log "ground truth eksport qilinmoqda"
docker cp harness/sql/dump-ground-truth.sql obsv-oracle:/tmp/ >/dev/null
ora /tmp/dump-ground-truth.sql > /dev/null 2>&1
docker cp obsv-oracle:/tmp/ground_truth.csv "$OUT/ground_truth.csv" >/dev/null

log "Kafka topigi eksport qilinmoqda"
docker exec obsv-kafka-1 /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic "$TOPIC" --from-beginning \
  --timeout-ms ${EXPORT_TIMEOUT_MS:-8000} --property print.timestamp=true --property print.partition=true --property print.offset=true 2>/dev/null \
  > "$OUT/sink.jsonl" || true

# ------------------------------------------------------------ 11. analyse ----
log "tahlil"
python3 harness/analyze.py \
  --ground-truth "$OUT/ground_truth.csv" --sink "$OUT/sink.jsonl" \
  --mode "$MODE" --profile "$PROFILE" --rep "$REP" --fault "$FAULT" \
  --json-out "$OUT/metrics.json" | tee -a "$OUT/run.log"

python3 harness/summarise.py "$OUT"

# ------------------------------------------------------------ 12. app down ----
# Leaving the application running holds its whole OLTP pool open. Those sessions count against
# the instance's processes limit and the next run then starts closer to the ORA-12516 ceiling,
# so each run tidies up after itself instead of relying on the next one to do it.
log "ilova va konnektor to'xtatilmoqda"
./scripts/register-connector.sh none >> "$OUT/run.log" 2>&1 || true

# Each Debezium run creates topics named after its unique prefix — the change topic, the
# heartbeat and the schema history. They were never removed, so 200 runs left 217 orphaned
# topics holding 23 GB per broker. The run that created them deletes them.
if [[ "$MODE" == CDC || "$MODE" == HYBRID ]]; then
  for t in $(docker exec obsv-kafka-1 /opt/kafka/bin/kafka-topics.sh \
               --bootstrap-server localhost:9092 --list 2>/dev/null | grep -F "$PREFIX" || true); do
    docker exec obsv-kafka-1 /opt/kafka/bin/kafka-topics.sh \
      --bootstrap-server localhost:9092 --delete --topic "$t" >/dev/null 2>&1 || true
  done
fi
kill "$APP_PID" 2>/dev/null || true
for i in $(seq 1 15); do
  ss -ltn 2>/dev/null | grep -q ":$APP_PORT " || break
  sleep 1
done

log "=== TUGADI: $OUT ==="
