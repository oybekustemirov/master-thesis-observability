#!/usr/bin/env bash
# Chains everything that is left of the empirical work, unattended:
#
#   Phase A (already running)  ->  Phase B faults  ->  V10  ->  C2a  ->  C2b  ->  analysis
#
# Every stage is resumable on its own, so an interruption costs the current cell and nothing
# else. Stages that would waste hours if their prerequisites are broken check those
# prerequisites first and stop rather than burning the time.
set -uo pipefail
cd "$(dirname "$0")/.."

LOG=results/run-all.log
say() { echo "[$(date '+%F %T')] [chain] $*" | tee -a "$LOG"; }

# --------------------------------------------------------- 0. wait for A ----
if pgrep -f '[r]un-matrix.sh' >/dev/null; then
  say "A fazasi hali ishlayapti — kutilmoqda"
  while pgrep -f '[r]un-matrix.sh' >/dev/null; do sleep 30; done
  say "A fazasi tugadi"
fi

say "=== A fazasi natijasi ==="
python3 harness/aggregate.py --summary results/summary.csv \
        --out results/aggregate-P1.md >/dev/null 2>&1 \
  && say "results/aggregate-P1.md yozildi" || say "OGOHLANTIRISH: agregatsiya bajarilmadi"

# ------------------------------------------- 1. self-test the repair path ----
# Phase B is worthless without a working repair between cells, and finding that out after six
# hours of runs is the expensive way to learn it. The repair is idempotent, so running it once
# on a healthy database is a safe check that it can do its job.
say "=== fault'dan keyingi tiklashni tekshirish ==="
if ./scripts/repair-after-fault.sh >>"$LOG" 2>&1; then
  say "tiklash yo'li ishlaydi"
else
  say "XATO: tiklash sog'lom bazada ham ishlamadi — B fazasi to'xtatildi"
  say "       B fazasisiz C2 ga o'tilmoqda"
  SKIP_B=1
fi

# ------------------------------------------------------------ 2. Phase B ----
if [[ "${SKIP_B:-0}" != 1 ]]; then
  say "=== B FAZASI: fault matritsasi ==="
  ./scripts/run-matrix.sh B >>"$LOG" 2>&1 || say "OGOHLANTIRISH: B fazasi xato bilan tugadi"
  say "B fazasi tugadi"
  for f in F1 F2 F8 F11 F4 F5; do
    python3 harness/aggregate.py --summary results/summary.csv --fault "$f" \
            --out "results/aggregate-$f.md" >/dev/null 2>&1 \
      && say "results/aggregate-$f.md yozildi"
  done
fi

# --------------------------------------------------- 3. apply V10 for C2 ----
# Held back until now on purpose: applying a migration between matrix cells would change the
# database underneath a comparison that assumes it constant.
PENDING=src/main/resources/db/migration/V10__redo_noise.sql.pending
TARGET=src/main/resources/db/migration/V10__redo_noise.sql
if [[ -f "$PENDING" ]]; then
  say "=== V10 (REDO_NOISE) qo'llanmoqda ==="
  mv "$PENDING" "$TARGET"
  if ./mvnw -q flyway:migrate >>"$LOG" 2>&1; then
    say "V10 qo'llandi"
  else
    say "XATO: V10 migratsiyasi bajarilmadi — C2 ishga tushmaydi"
    exit 1
  fi
fi

# ---------------------------------------------------- 4. C2 prerequisites ----
say "=== C2: shovqin havzasi va kalibratsiya ==="
./scripts/run-c2.sh seed >>"$LOG" 2>&1 || { say "XATO: seed bajarilmadi"; exit 1; }
if ./scripts/run-c2.sh calibrate >>"$LOG" 2>&1; then
  CAL=$(cat results/c2-calibration.txt 2>/dev/null | tr -d ' \r\n')
  # Must be a POSITIVE NUMBER, not merely non-empty. The first version tested only for
  # emptiness and "0", so when the calibration failed with ORA-14551 the guard saw a long
  # error string, judged it neither empty nor zero, and let the whole experiment proceed on a
  # calibration that did not exist. A guard that accepts anything it does not recognise is not
  # a guard.
  if [[ ! "$CAL" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "${CAL%%.*}" -le 0 ]]; then
    say "XATO: kalibratsiya son qaytarmadi ('${CAL:0:80}') — C2 to'xtatildi"
    exit 1
  fi
  say "kalibratsiya: yangilanish boshiga $CAL bayt redo"
else
  say "XATO: kalibratsiya bajarilmadi — C2 to'xtatildi"
  exit 1
fi

# ---------------------------------------------------------- 5. C2a, C2b ----
say "=== C2a: 5 daraja x {ON,OFF} x 3 takror ==="
./scripts/run-c2.sh a >>"$LOG" 2>&1 || say "OGOHLANTIRISH: C2a xato bilan tugadi"

say "=== C2b: qamrov kengligi ==="
./scripts/run-c2.sh b >>"$LOG" 2>&1 || say "OGOHLANTIRISH: C2b xato bilan tugadi"

# ------------------------------------------------------------ 6. analysis ----
say "=== C2 tahlili ==="
python3 harness/c2-analyze.py --summary results/summary.csv \
        --out results/c2-report.md --json-out results/c2-report.json >>"$LOG" 2>&1 \
  && say "results/c2-report.md yozildi" || say "OGOHLANTIRISH: C2 tahlili bajarilmadi"

say "=== HAMMASI TUGADI ==="
