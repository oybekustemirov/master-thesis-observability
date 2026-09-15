#!/usr/bin/env bash
# Brings the whole experiment stack up and leaves it ready for a run.
set -euo pipefail
cd "$(dirname "$0")/.."
COMPOSE="docker compose -f docker/docker-compose.yml"

echo "==> Stack ko'tarilmoqda (birinchi marta Connect image quriladi)"
$COMPOSE up -d --build

wait_healthy() {
  local svc=$1 max=${2:-90} i=0
  printf "    %s: " "$svc"
  while (( i < max )); do
    local st
    st=$($COMPOSE ps --format json "$svc" 2>/dev/null | head -1 | grep -oP '"Health":"\K[^"]*' || echo "")
    [[ "$st" == "healthy" ]] && { echo "healthy"; return 0; }
    printf "."; sleep 5; ((i++))
  done
  echo " TIMEOUT"; return 1
}

echo "==> Servislar kutilmoqda"
wait_healthy oracle 120
wait_healthy kafka-1
wait_healthy kafka-2
wait_healthy kafka-3

./scripts/setup-oracle.sh

wait_healthy connect 60 || echo "    (Connect hali ko'tarilmoqda — 'docker compose logs connect' ni ko'ring)"

cat <<EOF

==> Tayyor.

  Oracle          localhost:1521/OBSVPDB   obsv / Obsv_2026   (sys: Th3sis_Sys_2026)
  Kafka           localhost:19092, 29092, 39092   (RF=3, min.insync=2)
  Kafka Connect   http://localhost:8083
  Connect metrics http://localhost:9404/metrics
  Schema Registry http://localhost:8081
  Prometheus      http://localhost:9091
  Grafana         http://localhost:3000        (anonim kirish yoqilgan)
  Kafka UI        http://localhost:8090

  Keyingi qadam:  ./mvnw flyway:migrate
EOF
