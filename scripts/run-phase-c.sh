#!/usr/bin/env bash
# Runs after the main chain: applies V11, re-measures the noise calibration, and executes the
# corrected fault reruns (Phase C).
#
# Separate from run-all.sh on purpose. run-all.sh is already executing, and a running bash keeps
# reading from the inode it started with, so appending a phase to it would never be picked up.
set -uo pipefail
cd "$(dirname "$0")/.."

LOG=results/phase-c.log
say() { echo "[$(date '+%F %T')] [phase-c] $*" | tee -a "$LOG"; }
ora() { local f="$1"; shift; docker exec obsv-oracle bash -lc "sqlplus -S -L / as sysdba @$f $* </dev/null"; }

# ------------------------------------------------------- 0. wait for the chain ----
if pgrep -f '[r]un-all.sh' >/dev/null; then
  say "asosiy zanjir (C2) hali ishlayapti — kutilmoqda"
  while pgrep -f '[r]un-all.sh' >/dev/null; do sleep 60; done
  say "asosiy zanjir tugadi"
fi

# ------------------------------------------------------------- 1. apply V11 ----
PENDING=src/main/resources/db/migration/V11__batch_outbox_emission.sql.pending
TARGET=src/main/resources/db/migration/V11__batch_outbox_emission.sql
if [[ -f "$PENDING" ]]; then
  say "=== V11 (batch outbox emission) qo'llanmoqda ==="
  mv "$PENDING" "$TARGET"
  if ! ./mvnw -q flyway:migrate >>"$LOG" 2>&1; then
    say "XATO: V11 migratsiyasi bajarilmadi"; exit 1
  fi
fi

# V11 replaces PKG_SYNTH_DATA, which every single run calls through reset_workload. A package
# left INVALID here would break every subsequent cell, so the migration asserts its own result
# rather than trusting that "flyway said OK" means the package compiles.
cat > /tmp/verify-pkg.sql <<'SQL'
SET FEEDBACK OFF PAGESIZE 0 HEADING OFF TRIMSPOOL ON
ALTER SESSION SET CONTAINER = OBSVPDB;
SPOOL /tmp/pkg_status.txt
SELECT object_name || ':' || status FROM all_objects
 WHERE owner = 'OBSV' AND object_name IN ('PKG_SYNTH_DATA', 'PKG_A1_EVENT')
   AND object_type LIKE 'PACKAGE%';
SPOOL OFF
EXIT;
SQL
docker cp /tmp/verify-pkg.sql obsv-oracle:/tmp/ >/dev/null
ora /tmp/verify-pkg.sql >/dev/null 2>&1 || true
STATUS=$(docker exec obsv-oracle cat /tmp/pkg_status.txt 2>/dev/null | tr -d ' \r' | tr '\n' ' ')
say "paket holati: $STATUS"
if grep -q 'INVALID' <<<"$STATUS"; then
  say "XATO: paket INVALID — C fazasi to'xtatildi (aks holda har bir katak buziladi)"
  exit 1
fi

# --------------------------------------------------------- 2. recalibrate ----
# The first calibration failed with ORA-14551 and the chain's guard was too loose to notice.
# Both are fixed; this proves the fix before anything depends on it.
say "=== shovqin kalibratsiyasi qayta o'lchanmoqda ==="
if ./scripts/run-c2.sh calibrate >>"$LOG" 2>&1; then
  say "kalibratsiya: $(cat results/c2-calibration.txt 2>/dev/null) bayt/yangilanish"
else
  say "OGOHLANTIRISH: kalibratsiya baribir bajarilmadi — C2 moslashuvi bunga bog'liq emas, davom etilmoqda"
fi

# ------------------------------------------------------------ 3. phase C ----
say "=== C FAZASI: tuzatilgan fault qayta ishlashlari ==="
./scripts/run-matrix.sh C >>"$LOG" 2>&1 || say "OGOHLANTIRISH: C fazasi xato bilan tugadi"

# ------------------------------------------------------------ 4. analysis ----
for f in F1 F1R F2 F8 F11 F11B F4 F4R F5 F5R; do
  python3 harness/aggregate.py --summary results/summary.csv --fault "$f" \
          --out "results/aggregate-$f.md" >/dev/null 2>&1 \
    && say "results/aggregate-$f.md yozildi"
done
python3 harness/c2-analyze.py --summary results/summary.csv \
        --out results/c2-report.md --json-out results/c2-report.json >>"$LOG" 2>&1 \
  && say "results/c2-report.md yangilandi"

say "=== C FAZASI TUGADI ==="
