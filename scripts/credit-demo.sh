#!/usr/bin/env bash
# End-to-end demonstration: a credit application moves through the bank's stages, every
# transition is captured by the mechanism under test, and the events land on Kafka.
#
#   ./scripts/credit-demo.sh                # WRAPPER_B3 — no connector needed
#   ./scripts/credit-demo.sh HYBRID         # outbox relayed by Debezium
#
# This is the thesis in one command: the credit workflow driven through the capture mechanism
# that Chapters 5 and 6 measure.
set -uo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-WRAPPER_B3}"
PORT=8095
TOPIC=bank.credit.application.events
REF="DEMO-$(date +%H%M%S)"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
api() { curl -sS -X "$1" "localhost:$PORT$2" -H 'Content-Type: application/json' ${3:+-d "$3"}; }

# --------------------------------------------------------------- 1. topic ----
say "1/5  Kafka topigi tayyorlanmoqda: $TOPIC"
docker exec obsv-kafka-1 /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --delete --topic "$TOPIC" >/dev/null 2>&1 || true
sleep 4
docker exec obsv-kafka-1 /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic "$TOPIC" --partitions 3 --replication-factor 3 \
  --config min.insync.replicas=2 >/dev/null 2>&1 || true

# A connector left registered by an EARLIER demo is a second publisher. It streams
# A1_EVENT_OUTBOX from the redo log and routes by AGGREGATE_TYPE to this very topic, so a
# WRAPPER_B3 run - where the application publishes for itself - put every event on the topic
# twice: 9 outbox rows with 9 distinct event ids arrived as 18 messages. Removed before every
# run; the HYBRID/CDC branch below registers exactly the one this run needs.
for C in $(curl -s "localhost:8083/connectors" 2>/dev/null \
           | python3 -c 'import sys,json;print(" ".join(json.load(sys.stdin)))' 2>/dev/null); do
  curl -sS -X DELETE "localhost:8083/connectors/$C" >/dev/null 2>&1 && echo "     eski konnektor o'chirildi: $C"
done

# Credit outbox rows left over from an earlier run are marked published before this one starts.
# HYBRID never marks them — that is Debezium's job, and Debezium does not write back — so a later
# WRAPPER_B3 run finds them unpublished and replays them. Real deployments never mix the two
# modes; the demo does, so it tidies up first.
docker exec obsv-oracle bash -lc "sqlplus -S obsv/Obsv_2026@//localhost:1521/OBSVPDB <<'EOSQL' >/dev/null 2>&1
UPDATE A1_EVENT_OUTBOX SET PUBLISHED_AT = SYSTIMESTAMP
 WHERE AGGREGATE_TYPE = 'credit.application' AND PUBLISHED_AT IS NULL;
COMMIT;
EXIT;
EOSQL" || true

# ----------------------------------------------------------------- 2. app ----
say "2/5  Ilova ishga tushirilmoqda (mode=$MODE)"
# Wait until the port is ACTUALLY free rather than sleeping a fixed five seconds. A JVM that
# takes longer than that to exit leaves two instances briefly alive, and two outbox relays
# publish the same rows twice: the topic showed 18 messages for an application whose outbox held
# 9 rows with 9 distinct event ids.
PIDS=$(ss -ltnp 2>/dev/null | grep ":$PORT " | grep -oP 'pid=\K[0-9]+' | sort -u || true)
if [[ -n "$PIDS" ]]; then
  kill $PIDS 2>/dev/null
  for i in $(seq 1 30); do
    ss -ltn 2>/dev/null | grep -q ":$PORT " || break
    sleep 1
    [[ $i -eq 30 ]] && kill -9 $PIDS 2>/dev/null
  done
  # The port closes when the listener stops; the JVM needs a moment more to finish its last
  # relay tick and release its database session.
  sleep 3
fi
JAR=$(ls target/*.jar 2>/dev/null | grep -v sources | head -1)
[[ -n "$JAR" ]] || { echo "XATO: jar topilmadi, avval ./mvnw package -DskipTests"; exit 1; }
nohup java -jar "$JAR" --observability.mode="$MODE" > /tmp/credit-demo-app.log 2>&1 &
for i in $(seq 1 60); do
  curl -sf "localhost:$PORT/actuator/health" >/dev/null 2>&1 && break
  sleep 2
  if [[ $i -eq 60 ]]; then
    echo "XATO: ilova ko'tarilmadi"; tail -20 /tmp/credit-demo-app.log; exit 1
  fi
done
echo "     tayyor"

# In HYBRID and CDC the application publishes nothing at all: Debezium reads the row changes from
# the redo log. Registered AFTER the app so that the mode's supplemental-logging DDL is already
# applied, and BEFORE any workflow runs so the connector's starting SCN precedes the first event.
if [[ "$MODE" == HYBRID || "$MODE" == CDC ]]; then
  say "2b/5  Debezium konnektori ro'yxatdan o'tkazilmoqda ($MODE)"
  PREFIX="demo_$(echo "$MODE" | tr 'A-Z' 'a-z')_$(date +%H%M%S)"
  ./scripts/register-connector.sh "$MODE" "$PREFIX" 2>&1 | sed 's/^/     /' \
    || { echo "XATO: konnektor ishga tushmadi"; exit 1; }
fi

# --------------------------------------------------------- 3. the workflow ----
say "3/5  Ariza $REF yaratilmoqda va bosqichlardan o'tkazilmoqda"
api POST /api/credit "{\"appRef\":\"$REF\",\"customerRef\":\"CUST-000012345\",
  \"product\":\"IPOTEKA\",\"amount\":450000000,\"currency\":\"UZS\",\"channel\":\"FILIAL\",
  \"branchCode\":\"BR-001\",\"collateral\":true,\"actorId\":\"STF-00001\"}" >/dev/null
echo "     ariza kiritildi"

# Stages CHAIN: each one begins when the previous ended. The first version computed every
# stage as "now minus its own duration", so they all overlapped and a case whose stages summed
# to 149 hours spanned only 42 — a timeline an auditor would rightly call nonsense.
TOTAL_H=149
CURSOR=$(( $(date -u +%s) - TOTAL_H * 3600 ))
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# stage | hours the case spends IN it | hours before someone picks it up ("-" if nobody) |
# actor | role. The pickup split belongs to the stage where a person acts, which is what makes
# queue time separable from work time.
step() {
  local stage="$1" spent="$2" picked="$3" actor="$4" role="$5"
  local entered=$CURSOR
  local secs=$(python3 -c "print(int($spent*3600))")
  local completed=$(( entered + secs ))
  local pick="null"
  if [[ "$picked" != "-" ]]; then
    pick="\"$(iso $(( entered + $(python3 -c "print(int($picked*3600))") )))\""
  fi
  local actor_json="null"
  [[ "$actor" != "-" ]] && actor_json="\"$actor\""
  api POST "/api/credit/$REF/advance" "{\"toStage\":\"$stage\",
    \"enteredAt\":\"$(iso $entered)\",\"pickedUpAt\":$pick,
    \"completedAt\":\"$(iso $completed)\",
    \"actorId\":$actor_json,\"actorRole\":\"$role\",\"rework\":false}" \
    | python3 harness/credit-demo-report.py --single 2>/dev/null \
    || echo "     $stage yozildi"
  CURSOR=$completed
}

step TASHQI_TEKSHIRUV 20    -     -          TASHQI_TIZIM
step GAROV_BAHOLASH   41    -     -          BAHOLASH_KOMPANIYASI
step ANDERRAYTER      27.4  25.5  STF-00031  ANDERRAYTER
step QOMITA_KUTISH    42    -     -          QOMITA
step QOMITA_QARORI    0.4   0.0   STF-00061  QOMITA_AZOSI
step SUGURTA_NOTARIUS 7     -     -          SUGURTA_NOTARIUS
step SHARTNOMA        9     -     -          CUSTOMER
step AJRATISH         2.5   2.0   STF-00091  OPERATSION_XODIM

# -------------------------------------------------------------- 4. settle ----
say "4/5  Pipeline bo'shashi kutilmoqda"
# Debezium's mining cycle is seconds, not the outbox relay's 200 ms poll.
if [[ "$MODE" == HYBRID || "$MODE" == CDC ]]; then sleep 25; else sleep 12; fi

# -------------------------------------------------------------- 5. result ----
say "5/5  Kafka'ga tushgan hodisalar"
docker exec obsv-kafka-1 /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic "$TOPIC" --from-beginning \
  --timeout-ms 8000 2>/dev/null | python3 harness/credit-demo-report.py --ref "$REF"

if [[ "$MODE" == HYBRID || "$MODE" == CDC ]]; then
  say "Diqqat: bu rejimda ilova Kafka'ga UMUMAN yozmadi."
  echo "  Hodisalar A1_EVENT_OUTBOX jadvaliga yozildi va Debezium ularni redo logdan o'qidi."
fi

say "Ilova ishlab turibdi (port $PORT)."
echo "  To'xtatish:  kill \$(ss -ltnp | grep :$PORT | grep -oP 'pid=\K[0-9]+')"
