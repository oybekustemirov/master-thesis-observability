#!/usr/bin/env bash
# --volumes: ma'lumotlarni ham o'chiradi (eksperimentlar orasida toza start uchun)
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--volumes" ]]; then
  echo "==> Stack va BARCHA ma'lumotlar o'chirilmoqda"
  docker compose -f docker/docker-compose.yml down --volumes --remove-orphans
else
  echo "==> Stack to'xtatilmoqda (ma'lumotlar saqlanadi; tozalash uchun --volumes)"
  docker compose -f docker/docker-compose.yml down --remove-orphans
fi
