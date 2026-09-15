#!/usr/bin/env bash
# Experiment C2 — does LogMiner overhead track total redo or captured redo?
# Design: docs/experiment-c2-design.md
#
#   ./scripts/run-c2.sh seed         populate the noise pool (once)
#   ./scripts/run-c2.sh calibrate    measure redo bytes per noise update on this instance
#   ./scripts/run-c2.sh a            C2a: vary uncaptured redo, connector ON and OFF
#   ./scripts/run-c2.sh b            C2b: vary capture scope at constant total redo
#
# Cells are labelled with a distinct PROFILE (C2N0..C2N4, C2WIDE) rather than P1, so that C2
# rows can never be pooled with the main matrix's P1 rows by the aggregation script. Without
# that separation a C2 run and a Phase A run would share (mode=CDC, profile=P1, fault=none) and
# be indistinguishable in summary.csv.
set -uo pipefail
cd "$(dirname "$0")/.."

ACTION="${1:-a}"
REPS=${C2_REPS:-3}
TPS=${C2_TPS:-50}
DURATION=${C2_DURATION:-180s}
NOISE_WINDOW=${C2_NOISE_WINDOW:-420}   # covers setup + workload + settle for one cell
POOL_ROWS=${C2_POOL_ROWS:-50000}

PROGRESS=results/c2-progress.log
mkdir -p results

# Same guard as the main matrix, for the same reason: resumption is keyed on profile and rep
# alone, so a cell run at a different rate or duration would satisfy the skip check while being
# incomparable to the rest.
STAMP=results/c2-settings.txt
WANT="reps=$REPS tps=$TPS duration=$DURATION window=$NOISE_WINDOW levels=${C2_LEVELS:-default}"
if [[ -f "$STAMP" && "$(cat "$STAMP")" != "$WANT" ]]; then
  echo "XATO: C2 boshqa sozlamalar bilan boshlangan." >&2
  echo "  mavjud: $(cat "$STAMP")" >&2
  echo "  so'ralgan: $WANT" >&2
  exit 2
fi
echo "$WANT" > "$STAMP"
say() { echo "[$(date '+%F %T')] $*" | tee -a "$PROGRESS"; }
ora() { local f="$1"; shift; docker exec obsv-oracle bash -lc "sqlplus -S -L / as sysdba @$f $* </dev/null"; }
obsv() { local f="$1"; shift; docker exec obsv-oracle bash -lc \
         "sqlplus -S obsv/Obsv_2026@//localhost:1521/OBSVPDB @$f $* </dev/null"; }

push_sql() { docker cp "harness/sql/$1" obsv-oracle:/tmp/ >/dev/null; }

# ------------------------------------------------------------------ noise ----
stop_noise() {
  push_sql noise-stop.sql
  ora /tmp/noise-stop.sql >>"$PROGRESS" 2>&1 || true
}

start_noise() {
  local rate="$1"
  push_sql noise-run.sql
  # Detached: the procedure terminates itself after NOISE_WINDOW seconds, and stop_noise
  # clears anything that outlives its cell.
  ( obsv /tmp/noise-run.sql "$NOISE_WINDOW" "$rate" >/dev/null 2>&1 & ) 
}

# -------------------------------------------------------- supplemental log ----
# C2b holds TOTAL redo constant between the narrow and wide arms. ALL-column supplemental
# logging on REDO_NOISE changes how much redo Oracle WRITES, so it must be identical in both
# arms — enabled in both, not only in the arm that captures the table. Enabling it only for the
# wide arm would change the independent variable and confound the whole comparison.
set_noise_logging() {
  local on="$1" verb
  [[ "$on" == on ]] && verb=ADD || verb=DROP
  docker exec obsv-oracle bash -lc "sqlplus -S obsv/Obsv_2026@//localhost:1521/OBSVPDB <<'EOF' >/dev/null 2>&1
WHENEVER SQLERROR CONTINUE
ALTER TABLE REDO_NOISE $verb SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
EXIT;
EOF" || true
  say "REDO_NOISE supplemental logging -> $on"
}

# ------------------------------------------------------------------- cell ----
done_already() {
  local profile="$1" rep="$2"
  [[ -f results/summary.csv ]] || return 1
  awk -F, -v p="$profile" -v r="$rep" 'NR>1 && $3==p && $4==r {f=1} END{exit !f}' results/summary.csv
}

cell() {
  local profile="$1" rep="$2" rate="$3" connector="$4" tmpl="${5:-}"
  if done_already "$profile" "$rep"; then
    say "SKIP  $profile/r$rep"; return 0
  fi
  say "RUN   $profile/r$rep  (noise=${rate}/s, connector=$connector)"
  stop_noise
  [[ "$rate" -gt 0 ]] && start_noise "$rate"

  # --profile is the LABEL for summary.csv; --workload-profile is the k6 scenario. They were the
  # same argument once, and passing a C2 label to k6 selected a scenario that does not exist.
  # --fixed-settle makes the measured window identical in the connector-present and
  # connector-absent arms. Without it the arms differed by ~100 s of noise generation.
  local args=(--mode CDC --profile "$profile" --workload-profile P1 --fixed-settle "${C2_SETTLE:-45}"
              --rep "$rep" --tps "$TPS" --duration "$DURATION")
  [[ "$connector" == off ]] && args+=(--no-connector)
  [[ -n "$tmpl" ]] && export C2_CONNECTOR_TEMPLATE="$tmpl"

  if ./scripts/run-experiment.sh "${args[@]}" >/dev/null 2>&1; then
    say "OK    $profile/r$rep"
  else
    say "FAIL  $profile/r$rep (davom etilmoqda)"
  fi
  unset C2_CONNECTOR_TEMPLATE
  stop_noise
}

# ------------------------------------------------------------------ levels ----
# Expressed as updates per second. calibrate converts these to redo bytes per second on the
# instance actually used, and that conversion is recorded with the results.
LEVELS=(${C2_LEVELS:-0 1500 3000 6000 12000})

case "$ACTION" in

  seed)
    say "=== noise pool urug'lantirilmoqda ($POOL_ROWS satr) ==="
    docker exec obsv-oracle bash -lc "sqlplus -S obsv/Obsv_2026@//localhost:1521/OBSVPDB <<'EOF'
SET SERVEROUTPUT ON
BEGIN PKG_REDO_NOISE.seed($POOL_ROWS); END;
/
EXIT;
EOF" | tee -a "$PROGRESS"
    ;;

  calibrate)
    say "=== kalibratsiya: yangilanish boshiga redo bayt ==="
    push_sql noise-calibrate.sql
    obsv /tmp/noise-calibrate.sql >/dev/null 2>&1 || true
    BYTES=$(docker exec obsv-oracle cat /tmp/noise_cal.txt 2>/dev/null | tr -d ' \r\n')
    # Validated here as well as in the chain, so a manual invocation cannot quietly record a
    # SQL*Plus error message as a measurement.
    if [[ ! "$BYTES" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "${BYTES%%.*}" -le 0 ]]; then
      say "XATO: kalibratsiya son qaytarmadi: ${BYTES:0:120}"
      exit 1
    fi
    say "redo bytes per noise update: $BYTES"
    echo "$BYTES" > results/c2-calibration.txt
    for L in "${LEVELS[@]}"; do
      say "  level ${L}/s  ->  $(python3 -c "print(f'{$L*${BYTES}/1048576:.2f}')") MB/s redo"
    done
    ;;

  a)
    say "=== C2a: ${#LEVELS[@]} daraja x {ON,OFF} x $REPS takror ==="
    # Repetitions interleaved and the ON/OFF pair kept adjacent, for the same reason as the
    # main matrix: the subtraction assumes the two arms are comparable, which they are only if
    # nothing drifted between them.
    for rep in $(seq 1 "$REPS"); do
      say "--- takror $rep/$REPS ---"
      for i in "${!LEVELS[@]}"; do
        L=${LEVELS[$i]}
        cell "C2N${i}OFF" "$rep" "$L" off
        cell "C2N${i}ON"  "$rep" "$L" on
      done
    done
    ;;

  b)
    HIGH=${LEVELS[-1]}
    say "=== C2b: qamrov kengligi, shovqin ${HIGH}/s da qat'iy, $REPS takror ==="
    set_noise_logging on
    for rep in $(seq 1 "$REPS"); do
      say "--- takror $rep/$REPS ---"
      cell "C2NARROW" "$rep" "$HIGH" on cdc.json.tmpl
      cell "C2WIDE"   "$rep" "$HIGH" on cdc-wide.json.tmpl
    done
    set_noise_logging off
    ;;

  *)
    echo "noma'lum amal: $ACTION (seed | calibrate | a | b)" >&2; exit 2 ;;
esac

say "=== C2/$ACTION TUGADI ==="
