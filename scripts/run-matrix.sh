#!/usr/bin/env bash
# Runs the experiment matrix. Resumable, and safe to interrupt at any point.
#
#   ./scripts/run-matrix.sh A     clean cells: every mode x P1 x 5 repetitions
#   ./scripts/run-matrix.sh B     fault cells: the discriminating fault cases
#   ./scripts/run-matrix.sh A B   both, in order
#
# Two design decisions that matter more than they look.
#
# REPETITIONS ARE INTERLEAVED, NOT GROUPED. The loop runs repetition 1 of every mode, then
# repetition 2 of every mode, and so on. Grouping all five repetitions of a mode together would
# confound the mode with the time of day it ran at: background load, thermal state and page
# cache all drift over a matrix that takes hours, and a mode measured entirely within one such
# window carries that window's bias as if it were a property of the mechanism. Interleaving
# spreads every mode across the whole session. It also means an interrupted matrix still yields
# a BALANCED comparison at fewer repetitions rather than complete data for some modes and none
# for others.
#
# THE MODE ORDER ROTATES BY REPETITION. Within a repetition the modes always run in some order,
# and whichever runs first inherits a colder cache than whichever runs last. Rotating the list
# by the repetition index gives every mode each position across the five repetitions, so that
# systematic advantage cancels instead of accumulating. Rotation rather than shuffling keeps the
# schedule reproducible.
set -uo pipefail
cd "$(dirname "$0")/.."

PHASES=("$@")
[[ ${#PHASES[@]} -gt 0 ]] || PHASES=(A)

REPS=${REPS:-5}
TPS=${TPS:-50}
DURATION=${DURATION:-120s}
FAULT_REPS=${FAULT_REPS:-3}
FAULT_DURATION=${FAULT_DURATION:-180s}
FAULT_AT=${FAULT_AT:-60}

MODES=(OFF BASELINE_GT AQ WRAPPER_B1 WRAPPER_B2 WRAPPER_B3 CDC HYBRID)

PROGRESS=results/matrix-progress.log
mkdir -p results
say() { echo "[$(date '+%F %T')] $*" | tee -a "$PROGRESS"; }

# Resumption is keyed on (mode, profile, rep, fault) alone, so a cell run at a different rate or
# duration would satisfy the skip check while being incomparable to the rest of the matrix.
# That is not hypothetical: the first launch skipped BASELINE_GT/r1 because a 100 TPS / 60 s
# validation run from an earlier code revision happened to carry rep=1. The settings are
# therefore stamped on first use and enforced on every resume.
STAMP=results/matrix-settings.txt
WANT="reps=$REPS tps=$TPS duration=$DURATION fault_reps=$FAULT_REPS fault_duration=$FAULT_DURATION fault_at=$FAULT_AT"
if [[ -f "$STAMP" ]]; then
  HAVE=$(cat "$STAMP")
  if [[ "$HAVE" != "$WANT" ]]; then
    echo "XATO: bu matritsa boshqa sozlamalar bilan boshlangan." >&2
    echo "  mavjud: $HAVE" >&2
    echo "  so'ralgan: $WANT" >&2
    echo "Bir xil sozlamalar bilan davom eting yoki $STAMP va results/summary.csv ni arxivlang." >&2
    exit 2
  fi
else
  echo "$WANT" > "$STAMP"
fi

# A cell is done when summary.csv already holds a row with this mode/profile/rep/fault.
done_already() {
  local mode="$1" profile="$2" rep="$3" fault="$4"
  [[ -f results/summary.csv ]] || return 1
  awk -F, -v m="$mode" -v p="$profile" -v r="$rep" -v f="$fault" \
      'NR>1 && $2==m && $3==p && $4==r && $5==f {found=1} END{exit !found}' results/summary.csv
}

cell() {
  local mode="$1" profile="$2" rep="$3" fault="$4" tps="$5" dur="$6"
  if done_already "$mode" "$profile" "$rep" "$fault"; then
    say "SKIP  $mode/$profile/r$rep/$fault (allaqachon bajarilgan)"
    return 0
  fi
  local args=(--mode "$mode" --profile "$profile" --rep "$rep" --tps "$tps" --duration "$dur")
  if [[ "$fault" != none ]]; then
    # F5 has to be given a longer window than the others: its whole point is a transaction held
    # open past the connector's retention, so the hold must exceed 180 s AND the commit must
    # land inside the measured window. At the standard duration the run would end before the
    # transaction ever committed, and its absence from the topic would prove nothing.
    local at="$FAULT_AT"
    [[ "$fault" == F5 || "$fault" == F5R ]] && { dur="${F5_DURATION:-420s}"; at=30; args=(--mode "$mode" --profile "$profile" --rep "$rep" --tps "$tps" --duration "$dur"); }
    # F4R has to switch the redo log ten times and archive each switch before it deletes
    # anything, which does not fit inside the standard window.
    [[ "$fault" == F4R ]] && { dur="${F4R_DURATION:-300s}"; args=(--mode "$mode" --profile "$profile" --rep "$rep" --tps "$tps" --duration "$dur"); }
    args+=(--fault "$fault" --fault-at "$at")
  fi
  say "RUN   $mode/$profile/r$rep/$fault (duration=$dur)"
  if ./scripts/run-experiment.sh "${args[@]}" >/dev/null 2>&1; then
    say "OK    $mode/$profile/r$rep/$fault"
  else
    # A failed cell is recorded and skipped, never allowed to abort the matrix: losing six
    # hours of remaining runs because one cell failed is a worse outcome than a gap.
    say "FAIL  $mode/$profile/r$rep/$fault (davom etilmoqda)"
  fi
  # Faults leave permanent damage — a broken PL/SQL package, an open transaction, a stopped
  # container — that the NEXT cell would inherit and report as its own result. Repair runs
  # after every fault cell, and says so when it cannot finish.
  if [[ "$fault" != none ]]; then
    ./scripts/repair-after-fault.sh >>"$PROGRESS" 2>&1 \
      || say "OGOHLANTIRISH: fault'dan keyingi tiklash to'liq bo'lmadi — keyingi kataklar shubhali"
  fi
}

# Rotate an array by n positions and print it.
rotate() {
  local n="$1"; shift
  local -a a=("$@")
  local len=${#a[@]} i
  for ((i = 0; i < len; i++)); do printf '%s ' "${a[$(( (i + n) % len ))]}"; done
}

phase_A() {
  say "=== PHASE A: ${#MODES[@]} rejim x P1 x $REPS takror, ${TPS} tps, $DURATION ==="
  for rep in $(seq 1 "$REPS"); do
    say "--- takror $rep/$REPS ---"
    for mode in $(rotate "$rep" "${MODES[@]}"); do
      cell "$mode" P1 "$rep" none "$TPS" "$DURATION"
    done
  done
}

# Fault cases, each applied only to the modes it can actually discriminate between. Running a
# fault against a mode it cannot affect burns an hour to produce a row that says nothing.
phase_B() {
  say "=== PHASE B: fault matritsasi, $FAULT_REPS takror ==="
  declare -A FAULT_MODES=(
    [F1]="WRAPPER_B1 WRAPPER_B2 WRAPPER_B3 AQ CDC HYBRID"
    [F2]="WRAPPER_B1 WRAPPER_B2 WRAPPER_B3 AQ CDC HYBRID"
    [F8]="AQ"
    [F11]="WRAPPER_B3 AQ CDC HYBRID"
    [F4]="CDC HYBRID"
    [F5]="CDC HYBRID"
  )
  for rep in $(seq 1 "$FAULT_REPS"); do
    say "--- fault takror $rep/$FAULT_REPS ---"
    for fault in F1 F2 F8 F11 F4 F5; do
      for mode in ${FAULT_MODES[$fault]}; do
        cell "$mode" P1 "$rep" "$fault" "$TPS" "$FAULT_DURATION"
      done
    done
  done
}

# Corrected reruns of the four fault cases that did not measure what they were designed to.
# Deliberately carried under NEW labels rather than reusing F1/F4/F5: pooling runs taken before
# and after a measurement fix would hide the effect of the fix, which is itself a result worth
# reporting.
phase_C() {
  say "=== PHASE C: tuzatilgan fault qayta ishlashlari, $FAULT_REPS takror ==="
  declare -A RERUN_MODES=(
    # F1R  — identical fault, but the runner now revives the application and drains the
    #        pipeline before exporting, so "missing" means unrecoverable rather than undelivered.
    [F1R]="WRAPPER_B1 WRAPPER_B2 WRAPPER_B3 AQ CDC HYBRID"
    # F11B — the batch writes through EMIT_A1_EVENT. Only the two modes that failed F11 are
    #        rerun; AQ and CDC do not read the outbox and are unaffected by definition.
    [F11B]="WRAPPER_B3 HYBRID"
    # F4R  — ten log switches, each archived, before the archives are deleted.
    [F4R]="CDC HYBRID"
    # F5R  — the long transaction now writes outbox rows, so retention is what is tested.
    [F5R]="CDC HYBRID"
  )
  for rep in $(seq 1 "$FAULT_REPS"); do
    say "--- tuzatilgan takror $rep/$FAULT_REPS ---"
    for fault in F1R F11B F4R F5R; do
      for mode in ${RERUN_MODES[$fault]}; do
        cell "$mode" P1 "$rep" "$fault" "$TPS" "$FAULT_DURATION"
      done
    done
  done
}

START=$(date +%s)
for phase in "${PHASES[@]}"; do
  case "$phase" in
    A) phase_A ;;
    B) phase_B ;;
    C) phase_C ;;
    *) say "noma'lum faza: $phase" ;;
  esac
done
say "=== MATRITSA TUGADI ($(( ($(date +%s) - START) / 60 )) daqiqa) ==="
