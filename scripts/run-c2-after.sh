#!/usr/bin/env bash
# Runs C2 once Phase C has finished. The two cannot overlap: both reset the workload and both
# drive the same database, so running them together would make each the other's noise.
set -uo pipefail
cd "$(dirname "$0")/.."
LOG=results/c2-after.log
say() { echo "[$(date '+%F %T')] [c2-after] $*" | tee -a "$LOG"; }

if pgrep -f '[r]un-phase-c.sh' >/dev/null || pgrep -f '[r]un-matrix.sh C' >/dev/null; then
  say "C fazasi ishlayapti — kutilmoqda"
  while pgrep -f '[r]un-phase-c.sh' >/dev/null || pgrep -f '[r]un-matrix.sh C' >/dev/null; do sleep 60; done
  say "C fazasi tugadi"
fi

say "=== C2 (simmetrik o'lchov oynasi bilan) ==="
./scripts/run-c2.sh a >>"$LOG" 2>&1 || say "OGOHLANTIRISH: C2a xato bilan tugadi"
./scripts/run-c2.sh b >>"$LOG" 2>&1 || say "OGOHLANTIRISH: C2b xato bilan tugadi"

python3 harness/c2-analyze.py --summary results/summary.csv \
        --out results/c2-report.md --json-out results/c2-report.json >>"$LOG" 2>&1 \
  && say "results/c2-report.md yozildi"
for f in F1 F1R F2 F8 F11 F11B F4 F4R F5 F5R; do
  python3 harness/aggregate.py --summary results/summary.csv --fault "$f" \
          --out "results/aggregate-$f.md" >/dev/null 2>&1 && say "aggregate-$f.md"
done
say "=== TUGADI ==="
