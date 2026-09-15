#!/usr/bin/env bash
# Registers the Debezium connector for a CDC or HYBRID run, and does not return until the
# connector is genuinely streaming.
#
#   ./scripts/register-connector.sh CDC    <prefix>
#   ./scripts/register-connector.sh HYBRID <prefix>
#   ./scripts/register-connector.sh none            # remove every connector
#
# The prefix must be UNIQUE PER RUN. Debezium stores its committed offset in
# _connect_offsets keyed by the topic prefix, so reusing a prefix makes a new run resume from
# the previous run's SCN and replay its events. Those replayed events have no matching row in
# the freshly reset GROUND_TRUTH table, so reconciliation would report them as PHANTOM events —
# the exact signature of the dual-write anti-pattern, attributed to a pipeline that is innocent.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:?mode kerak: CDC | HYBRID | none}"
PREFIX="${2:-}"
CONNECT=http://localhost:8083
BOOTSTRAP=localhost:9092

drop_all() {
  for c in $(curl -sf "$CONNECT/connectors" | python3 -c 'import sys,json;print(" ".join(json.load(sys.stdin)))' 2>/dev/null || true); do
    echo "connector o'chirilmoqda: $c"
    curl -sf -X DELETE "$CONNECT/connectors/$c" >/dev/null || true
  done
  # Deleting is asynchronous; the task keeps its LogMiner session for a moment afterwards.
  sleep 3
}

drop_all
[[ "$MODE" == "none" ]] && exit 0
[[ -n "$PREFIX" ]] || { echo "XATO: prefix kerak" >&2; exit 2; }

case "$MODE" in
  CDC)    TMPL=docker/connect/connectors/cdc.json.tmpl ;;
  HYBRID) TMPL=docker/connect/connectors/hybrid.json.tmpl ;;
  *) echo "XATO: bu rejim konnektor talab qilmaydi: $MODE" >&2; exit 2 ;;
esac

# Experiment C2b compares a narrow and a wide capture scope, which is the same connector class
# with a different table.include.list. Overriding the template here keeps the two arms
# identical in every other respect — the two files differ in exactly one key.
if [[ -n "${C2_CONNECTOR_TEMPLATE:-}" ]]; then
  TMPL="docker/connect/connectors/$C2_CONNECTOR_TEMPLATE"
  [[ -f "$TMPL" ]] || { echo "XATO: shablon topilmadi: $TMPL" >&2; exit 2; }
  echo "C2 shabloni ishlatilmoqda: $TMPL"
fi

NAME="a1-$(echo "$MODE" | tr 'A-Z' 'a-z')-$PREFIX"
CFG=$(mktemp)
sed -e "s|__NAME__|$NAME|g" -e "s|__PREFIX__|$PREFIX|g" "$TMPL" > "$CFG"

echo "konnektor ro'yxatdan o'tkazilmoqda: $NAME (prefix=$PREFIX)"
HTTP=$(curl -s -o /tmp/connector-post.out -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
        --data @"$CFG" "$CONNECT/connectors")
if [[ "$HTTP" != 20* && "$HTTP" != 201 ]]; then
  echo "XATO: konnektor yaratilmadi (HTTP $HTTP)" >&2; cat /tmp/connector-post.out >&2; exit 1
fi

# ---------------------------------------------------------------- 1. RUNNING ----
for i in $(seq 1 60); do
  STATE=$(curl -sf "$CONNECT/connectors/$NAME/status" \
          | python3 -c 'import sys,json;d=json.load(sys.stdin);ts=d.get("tasks") or [{}];print(d["connector"]["state"]+"/"+ts[0].get("state","NONE"))' 2>/dev/null || echo "?/?")
  case "$STATE" in
    RUNNING/RUNNING) echo "konnektor RUNNING (${i}s)"; break ;;
    *FAILED*) echo "XATO: konnektor FAILED" >&2
              curl -s "$CONNECT/connectors/$NAME/status" | head -c 2000 >&2; exit 1 ;;
  esac
  sleep 1
  [[ $i -eq 60 ]] && { echo "XATO: konnektor RUNNING holatiga o'tmadi ($STATE)" >&2; exit 1; }
done

# -------------------------------------------------------------- 2. STREAMING ----
# RUNNING only means the task started. Oracle connectors then build the LogMiner session and
# resolve the starting SCN, which takes several more seconds. Starting the workload during that
# window loses the earliest transactions, and an intermittent gap at the head of every run is
# indistinguishable from genuine pipeline loss. A heartbeat message on the bus proves the
# streaming loop has actually begun.
HB="__debezium-heartbeat.$PREFIX"
echo "streaming tasdiqlanmoqda (heartbeat topigi: $HB)"
for i in $(seq 1 40); do
  # Check for task failure FIRST. A task can start and then die on the very next step — the
  # Oracle connector's schema snapshot is one such step — and without this check the loop
  # would spend minutes waiting for a heartbeat that a dead task can never send.
  TSTATE=$(curl -sf "$CONNECT/connectors/$NAME/status" \
           | python3 -c 'import sys,json;ts=(json.load(sys.stdin).get("tasks") or [{}]);print(ts[0].get("state","NONE"))' 2>/dev/null || echo "?")
  if [[ "$TSTATE" == "FAILED" ]]; then
    echo "XATO: konnektor topshirig'i FAILED holatiga o'tdi" >&2
    curl -s "$CONNECT/connectors/$NAME/status" \
      | python3 -c 'import sys,json;ts=(json.load(sys.stdin).get("tasks") or [{}]);print(ts[0].get("trace","")[:1500])' >&2
    exit 1
  fi
  COUNT=$(docker exec obsv-kafka-1 /opt/kafka/bin/kafka-console-consumer.sh \
            --bootstrap-server "$BOOTSTRAP" --topic "$HB" --from-beginning \
            --max-messages 1 --timeout-ms 2000 2>/dev/null | wc -l || echo 0)
  [[ "${COUNT:-0}" -ge 1 ]] && { echo "streaming tasdiqlandi (${i} urinish)"; exit 0; }
done
echo "XATO: heartbeat kelmadi - konnektor streaming qilmayapti" >&2
curl -s "$CONNECT/connectors/$NAME/status" | head -c 2000 >&2
exit 1
