#!/usr/bin/env python3
"""
Aggregates the experiment matrix into the tables the thesis reports.

Three things this does that a spreadsheet average would not:

  * REPORTS MEDIAN AND IQR, NOT MEAN AND SD. Latency and redo distributions here are skewed and
    the samples are small; a mean over five repetitions is dragged by one slow run and an SD
    computed from five points is not a meaningful interval.

  * POOLS RELIABILITY ACROSS REPETITIONS BEFORE BOUNDING IT. Loss is a property of the whole
    sample, not something to average. Five runs of 18 000 transitions with no loss is 90 000
    trials, and the Rule of Three bound tightens accordingly — from 167 ppm at one run to about
    33 ppm at five. Averaging five per-run bounds would throw that away.

  * USES AN EXACT PERMUTATION TEST. With five repetitions per arm the normal approximation
    behind the usual Mann-Whitney p-value is not valid. The exact two-sided p-value is computed
    by enumerating all C(10,5) = 252 assignments, which is also the reason no claim of
    significance is possible below p = 2/252 = 0.0079 at this sample size.
"""
import argparse
import csv
import math
import statistics
from collections import defaultdict
from itertools import combinations

# Metrics summarised per cell. (column, label, decimals, lower_is_better)
METRICS = [
    ("redo_bytes_per_transition", "redo bytes/transition", 0, True),
    ("latency_ms_p50",            "latency p50 (ms)",      0, True),
    ("latency_ms_p95",            "latency p95 (ms)",      0, True),
    ("latency_ms_p99",            "latency p99 (ms)",      0, True),
    ("http_p95_ms",               "HTTP p95 (ms)",         2, True),
    ("http_p99_ms",               "HTTP p99 (ms)",         2, True),
    ("achieved_tps",              "achieved TPS",          1, False),
    ("user_commits_delta",        "user commits",          0, True),
]

MODE_ORDER = ["OFF", "BASELINE_GT", "AQ", "WRAPPER_B1", "WRAPPER_B2", "WRAPPER_B3",
              "CDC", "HYBRID"]


def num(value):
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    return None if math.isnan(v) else v


def iqr(values):
    """Quartiles by the same rule as numpy's linear interpolation, so figures reconcile."""
    s = sorted(values)
    if len(s) == 1:
        return s[0], s[0]
    def q(p):
        pos = p * (len(s) - 1)
        lo = math.floor(pos)
        hi = math.ceil(pos)
        return s[lo] + (s[hi] - s[lo]) * (pos - lo)
    return q(0.25), q(0.75)


def mann_whitney_exact(a, b, max_enum=200_000):
    """Exact two-sided permutation p-value for the Mann-Whitney U statistic.

    Ties are handled by counting them as half a win, and by permuting the OBSERVED values
    rather than their ranks, which makes the null distribution correct even when ties exist.
    Falls back to the normal approximation only when enumeration would be too large.
    """
    n, m = len(a), len(b)
    if n == 0 or m == 0:
        return None, None

    def u_stat(x, y):
        return sum((1.0 if p > q else 0.5 if p == q else 0.0) for p in x for q in y)

    observed = u_stat(a, b)
    centre = n * m / 2.0

    pooled = list(a) + list(b)
    total = math.comb(n + m, n)
    if total > max_enum:
        # Normal approximation with a continuity correction; reported only for large samples.
        sd = math.sqrt(n * m * (n + m + 1) / 12.0)
        if sd == 0:
            return observed, 1.0
        z = (abs(observed - centre) - 0.5) / sd
        p = 2 * (1 - 0.5 * (1 + math.erf(z / math.sqrt(2))))
        return observed, min(1.0, p)

    extreme = 0
    idx = range(n + m)
    for pick in combinations(idx, n):
        chosen = set(pick)
        x = [pooled[i] for i in idx if i in chosen]
        y = [pooled[i] for i in idx if i not in chosen]
        if abs(u_stat(x, y) - centre) >= abs(observed - centre) - 1e-9:
            extreme += 1
    return observed, extreme / total


def hodges_lehmann(a, b):
    """Median of all pairwise differences: the location shift estimate that pairs with the
    Mann-Whitney test, and the number worth quoting alongside a p-value."""
    diffs = sorted(x - y for x in a for y in b)
    return statistics.median(diffs) if diffs else None


def load(path, fault, profile):
    """Filters on profile as well as fault.

    Experiment C2 records its cells under profiles C2N0..C2N4, C2NARROW and C2WIDE while still
    running mode=CDC. Without the profile filter those rows would be pooled with the main
    matrix's P1 CDC rows, which measure a different thing under a different noise condition.
    """
    cells = defaultdict(list)
    with open(path) as fh:
        for row in csv.DictReader(fh):
            if row.get("fault", "none") != fault:
                continue
            if profile and row.get("profile") != profile:
                continue
            cells[row["mode"]].append(row)
    return cells


def fmt(value, decimals):
    if value is None:
        return "—"
    return f"{value:,.{decimals}f}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", default="results/summary.csv")
    ap.add_argument("--fault", default="none", help="which fault's cells to aggregate")
    ap.add_argument("--profile", default="P1",
                    help="workload profile to aggregate; pass an empty string to pool all")
    ap.add_argument("--reference", default="BASELINE_GT",
                    help="mode each other mode is tested against")
    ap.add_argument("--out", default="", help="write the markdown report here as well")
    args = ap.parse_args()

    cells = load(args.summary, args.fault, args.profile)
    if not cells:
        print(f"'{args.fault}' / profile '{args.profile}' uchun qator topilmadi: {args.summary}")
        return

    modes = [m for m in MODE_ORDER if m in cells] + \
            sorted(m for m in cells if m not in MODE_ORDER)
    out = []
    w = out.append

    shown = args.profile or "all"
    w(f"# Matrix aggregate — profile `{shown}`, fault `{args.fault}`\n")
    reps = {m: len(cells[m]) for m in modes}
    w(f"Repetitions per mode: " + ", ".join(f"`{m}` = {reps[m]}" for m in modes) + "\n")

    # ---------------------------------------------------------------- reliability ----
    w("\n## Reliability, pooled across repetitions\n")
    w("| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |")
    w("|---|---|---|---|---|---|---|---|---|")
    for m in modes:
        rows = cells[m]
        gt = sum(int(float(r["ground_truth_transitions"] or 0)) for r in rows)
        if m in ("OFF", "BASELINE_GT"):
            w(f"| `{m}` | {len(rows)} | {gt:,} | — | — | — | — | baseline, no pipeline | — |")
            continue
        miss = sum(int(float(r["missing"] or 0)) for r in rows)
        phan = sum(int(float(r["phantom"] or 0)) for r in rows)
        dups = [num(r["duplicate_rate"]) for r in rows if num(r["duplicate_rate"]) is not None]
        ovrs = [num(r["ordering_violation_rate"]) for r in rows if num(r["ordering_violation_rate"]) is not None]
        if miss == 0 and gt:
            # Rule of Three: with zero observed failures in n trials the 95% upper bound on the
            # true rate is 3/n. Stating "loss rate = 0" from a finite sample is unfalsifiable.
            bound = f"< {3.0 / gt * 1e6:,.1f} ppm"
            rate = "0 observed"
        else:
            bound = "—"
            rate = f"{miss / gt * 1e6:,.1f} ppm" if gt else "—"
        w(f"| `{m}` | {len(rows)} | {gt:,} | {miss} | {phan} | "
          f"{max(dups) if dups else 0:.4f} | {max(ovrs) if ovrs else 0:.4f} | {rate} | {bound} |")
    w("\nDuplicate and ordering columns report the WORST run, not the mean: a defect that appears "
      "in one repetition out of five is a property of the mechanism, and averaging it away is "
      "how an intermittent fault gets written up as absent.\n")

    # ------------------------------------------------------------------- metrics ----
    for column, label, decimals, lower_better in METRICS:
        series = {}
        for m in modes:
            vals = [num(r[column]) for r in cells[m]]
            vals = [v for v in vals if v is not None]
            if vals:
                series[m] = vals
        if not series:
            continue
        w(f"\n## {label}\n")
        w("| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |")
        w("|---|---|---|---|---|---|---|")
        ref = series.get(args.reference)
        for m in modes:
            if m not in series:
                continue
            vals = series[m]
            med = statistics.median(vals)
            q1, q3 = iqr(vals)
            if m == args.reference or ref is None:
                delta = shift = pval = "—"
            else:
                refmed = statistics.median(ref)
                delta = f"{(med - refmed) / refmed * 100:+.1f} %" if refmed else "—"
                hl = hodges_lehmann(vals, ref)
                _, p = mann_whitney_exact(vals, ref)
                shift = fmt(hl, decimals)
                # At n=5 vs n=5 the smallest attainable two-sided p is 2/252 = 0.0079.
                pval = "—" if p is None else (f"**{p:.4f}**" if p < 0.05 else f"{p:.4f}")
            w(f"| `{m}` | {len(vals)} | {fmt(med, decimals)} | "
              f"{fmt(q1, decimals)}–{fmt(q3, decimals)} | {delta} | {shift} | {pval} |")

    w(f"\n---\n\nComparisons are against `{args.reference}`. The p-value is an exact two-sided "
      "permutation test on the Mann-Whitney U statistic; with five repetitions per arm the "
      "smallest attainable value is 0.0079, so no result here can be significant beyond that. "
      "\"shift (H-L)\" is the Hodges-Lehmann estimator, the median of all pairwise differences — "
      "the magnitude that belongs next to the p-value.\n")

    report = "\n".join(out)
    print(report)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(report + "\n")


if __name__ == "__main__":
    main()
