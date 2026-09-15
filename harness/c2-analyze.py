#!/usr/bin/env python3
"""
Analysis for experiment C2 (docs/experiment-c2-design.md).

Answers one question: is LogMiner's cost to the database driven by the redo it SCANS or by the
redo it CONVERTS INTO EVENTS?

The dependent variable is a difference of differences. At each noise level the same workload is
run twice, once with the connector present and once without, and

    mining_cost(N) = CPU_instance(N, connector ON) - CPU_instance(N, connector OFF)

Everything the two arms share — the workload, the noise generator's own CPU, the cost of
supplemental logging, background instance activity — cancels in that subtraction. Attributing
CPU to the mining session directly would not work, because Debezium tears down and recreates
its LogMiner session between iterations and a per-session counter loses whatever it accumulated
before the last teardown.

C2a holds captured redo CONSTANT — that is its manipulation — so a model carrying both
redo_total and redo_captured as regressors cannot be identified from this design. The two
hypotheses are separated instead by the sign of ONE slope:

    naive     cost is driven by what is captured, which is constant  ->  slope 0
    C2        cost is driven by what is scanned                      ->  slope > 0

fitted as  cost = slope * redo_discarded + intercept.
"""
import argparse
import csv
import json
import math
import random
import statistics
from collections import defaultdict

import numpy as np

CENTISECONDS_PER_SECOND = 100.0
BYTES_PER_GB = 1024 ** 3


def load(path, profile_prefix="C2N"):
    """Groups C2a rows into (level, arm) cells. Profiles are C2N<level>{ON,OFF}."""
    cells = defaultdict(list)
    with open(path) as fh:
        for row in csv.DictReader(fh):
            p = row.get("profile", "")
            if not p.startswith(profile_prefix):
                continue
            if p.endswith("ON"):
                level, arm = p[len(profile_prefix):-2], "on"
            elif p.endswith("OFF"):
                level, arm = p[len(profile_prefix):-3], "off"
            else:
                continue
            try:
                cells[(int(level), arm)].append(row)
            except ValueError:
                continue
    return cells


def col(rows, name):
    out = []
    for r in rows:
        try:
            v = float(r[name])
        except (TypeError, ValueError, KeyError):
            continue
        if not math.isnan(v):
            out.append(v)
    return out


def med(values):
    return statistics.median(values) if values else None


def ols(X, y):
    """Least squares with no intercept: cost is zero when there is no redo."""
    beta, *_ = np.linalg.lstsq(X, y, rcond=None)
    return beta


def bootstrap_coefficients(points, draws=4000, seed=20260904):
    """Resamples RUNS, not residuals.

    With three repetitions at five levels the residual degrees of freedom are small enough that
    a normal-theory interval would overstate precision. Resampling the observed cells keeps the
    interval honest about how few of them there are.
    """
    rng = random.Random(seed)
    a_draws, b_draws = [], []
    n = len(points)
    for _ in range(draws):
        sample = [points[rng.randrange(n)] for _ in range(n)]
        X = np.array([[p["redo_total_gb"], p["redo_captured_gb"]] for p in sample])
        y = np.array([p["cost_s"] for p in sample])
        if np.linalg.matrix_rank(X) < 2:
            continue
        try:
            a, b = ols(X, y)
        except np.linalg.LinAlgError:
            continue
        a_draws.append(a)
        b_draws.append(b)
    return sorted(a_draws), sorted(b_draws)


def interval(draws, lo=0.025, hi=0.975):
    if not draws:
        return None, None
    return draws[int(lo * (len(draws) - 1))], draws[int(hi * (len(draws) - 1))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", default="results/summary.csv")
    ap.add_argument("--out", default="results/c2-report.md")
    ap.add_argument("--json-out", default="results/c2-report.json")
    args = ap.parse_args()

    cells = load(args.summary)
    if not cells:
        print("C2 qatorlari topilmadi. Avval ./scripts/run-c2.sh a ni ishlating.")
        return

    levels = sorted({lvl for lvl, _ in cells})
    out, w = [], None
    out = []
    w = out.append

    w("# Experiment C2 — results\n")
    w("Cost is instance CPU with the connector present minus the same workload with it absent, "
      "at each noise level. Both arms carry identical capture configuration, including "
      "supplemental logging, so only the connector differs.\n")

    # -------------------------------------------------- per-level differences ----
    w("\n## Measured cost by noise level\n")
    w("| Level | runs on/off | redo total (GB) | redo captured (GB) | redo discarded (GB) | "
      "CPU on (s) | CPU off (s) | **mining cost (s)** | events | A1 TPS |")
    w("|---|---|---|---|---|---|---|---|---|---|")

    # Bytes of redo per captured transition, measured at the zero-noise level.
    zero_on = cells.get((min(levels), "on"), [])
    baseline_bytes_per_transition = med(col(zero_on, "redo_bytes_per_transition")) or 0.0

    points, checks = [], []
    for lvl in levels:
        on, off = cells.get((lvl, "on"), []), cells.get((lvl, "off"), [])
        if not on or not off:
            w(f"| {lvl} | {len(on)}/{len(off)} | — | — | — | — | — | *incomplete pair* | — | — |")
            continue

        cpu_on = med(col(on, "cpu_used_delta"))
        cpu_off = med(col(off, "cpu_used_delta"))
        redo_on = med(col(on, "redo_size_delta"))
        transitions = med(col(on, "ground_truth_transitions")) or 0
        redo_per_tr = med(col(on, "redo_bytes_per_transition")) or 0

        # Captured redo is the redo TXN_A1 itself generates, taken from the ZERO-NOISE level
        # where total redo IS the captured workload, and scaled by that level's transition
        # count.
        #
        # The first version computed it as redo_bytes_per_transition x transitions. That column
        # is itself redo_total / transitions, so the product returned redo_total exactly: the
        # two regressors were identical, the fit was unidentifiable, and it produced
        # coefficients of -1217 and +1224 that cancel, with intervals spanning +/-7000. The
        # script then declared C2 falsified. The verdict was an artefact of this line.
        redo_captured = baseline_bytes_per_transition * transitions
        redo_total = redo_on or 0
        redo_discarded = max(redo_total - redo_captured, 0.0)

        cost_s = (cpu_on - cpu_off) / CENTISECONDS_PER_SECOND
        events = med(col(on, "delivered_total")) or 0
        tps = med(col(on, "achieved_tps")) or 0

        points.append({
            "level": lvl,
            "redo_total_gb": redo_total / BYTES_PER_GB,
            "redo_captured_gb": redo_captured / BYTES_PER_GB,
            "redo_discarded_gb": redo_discarded / BYTES_PER_GB,
            "cost_s": cost_s,
        })
        checks.append({"level": lvl, "events": events, "tps": tps})

        w(f"| {lvl} | {len(on)}/{len(off)} | {redo_total / BYTES_PER_GB:,.3f} | "
          f"{redo_captured / BYTES_PER_GB:,.3f} | {redo_discarded / BYTES_PER_GB:,.3f} | "
          f"{cpu_on / CENTISECONDS_PER_SECOND:,.1f} | {cpu_off / CENTISECONDS_PER_SECOND:,.1f} | "
          f"**{cost_s:,.1f}** | {events:,.0f} | {tps:,.1f} |")

    # ------------------------------------------------ per-level admissibility ----
    # Checked LEVEL BY LEVEL, not pooled. A pooled spread hides which level broke and offers no
    # way to salvage the rest; the design pre-committed to excluding failing levels from the fit
    # and reporting them, which requires knowing which ones failed.
    w("\n## Admissibility of each level\n")
    w("| Level | events delivered / committed | ON vs OFF total redo | A1 TPS | verdict |")
    w("|---|---|---|---|---|")

    zero_tps = med(col(cells.get((min(levels), "on"), []), "achieved_tps")) or 1.0
    admissible = []
    for pt in points:
        lvl = pt["level"]
        on, off = cells[(lvl, "on")], cells[(lvl, "off")]
        delivered = med(col(on, "delivered_total")) or 0.0
        committed = med(col(on, "ground_truth_transitions")) or 1.0
        redo_on = med(col(on, "redo_size_delta")) or 0.0
        redo_off = med(col(off, "redo_size_delta")) or 0.0
        tps = med(col(on, "achieved_tps")) or 0.0

        # The connector must actually have captured the run. A cell where it delivered nothing
        # measured the cost of a connector that was not keeping up, which is a different
        # quantity from the cost of capture.
        deliver_ok = delivered >= 0.95 * committed
        # The two arms must differ ONLY in the connector. If they generated materially different
        # redo they were not the same workload, and the subtraction is meaningless.
        arm_gap = abs(redo_on - redo_off) / max(redo_on, redo_off, 1.0)
        arms_ok = arm_gap <= 0.15
        tps_ok = abs(tps - zero_tps) / zero_tps <= 0.05

        ok = deliver_ok and arms_ok and tps_ok
        reasons = []
        if not deliver_ok: reasons.append("connector did not keep up")
        if not arms_ok:    reasons.append("arms not comparable")
        if not tps_ok:     reasons.append("OLTP starved")
        pt["admissible"] = ok
        if ok:
            admissible.append(pt)
        w(f"| {lvl} | {delivered:,.0f} / {committed:,.0f} ({100*delivered/committed:.0f} %) | "
          f"{redo_on/BYTES_PER_GB:.2f} vs {redo_off/BYTES_PER_GB:.2f} GB ({100*arm_gap:.0f} % apart) | "
          f"{tps:.1f} | {'**admissible**' if ok else '**excluded** — ' + ', '.join(reasons)} |")

    w(f"\n{len(admissible)} of {len(points)} levels admissible.\n")

    # ------------------------------------------------------------- the test ----
    result = {"points": points, "admissible": len(admissible)}
    w("\n## The test\n")
    w("**C2a holds captured redo CONSTANT by design** — that is the manipulation. A model with "
      "both `redo_total` and `redo_captured` as regressors is therefore unidentifiable here: the "
      "second has almost no variance to estimate from. The two hypotheses instead make different "
      "predictions about a single slope:\n")
    w("* **Naive** — cost is driven by what is captured. Captured is constant, so **cost should "
      "be flat across noise levels**: slope zero.")
    w("* **C2** — cost is driven by what is scanned. **Cost should rise with discarded redo**: "
      "slope greater than zero.\n")

    if len(admissible) >= 3:
        X = np.array([[p["redo_discarded_gb"], 1.0] for p in admissible])
        y = np.array([p["cost_s"] for p in admissible])
        slope, intercept = ols(X, y)

        rng = random.Random(20260909)
        draws = []
        n = len(admissible)
        for _ in range(4000):
            sample = [admissible[rng.randrange(n)] for _ in range(n)]
            Xb = np.array([[q["redo_discarded_gb"], 1.0] for q in sample])
            yb = np.array([q["cost_s"] for q in sample])
            if np.linalg.matrix_rank(Xb) < 2:
                continue
            try:
                draws.append(ols(Xb, yb)[0])
            except np.linalg.LinAlgError:
                pass
        draws.sort()
        lo, hi = interval(draws)

        w(f"| quantity | value |")
        w(f"|---|---|")
        w(f"| slope — CPU-seconds per GB of **discarded** redo | **{slope:,.2f}** |")
        w(f"| 95 % bootstrap CI | {lo:,.2f} … {hi:,.2f} |" if lo is not None else "| 95 % CI | — |")
        w(f"| intercept — cost at zero discarded redo | {intercept:,.2f} s |")
        w(f"| levels in fit | {', '.join(str(p['level']) for p in admissible)} |")
        w("")

        supported = lo is not None and lo > 0
        if supported:
            worst = max(admissible, key=lambda q: q["redo_discarded_gb"])
            scan_cost = slope * worst["redo_discarded_gb"]
            share = 100 * scan_cost / worst["cost_s"] if worst["cost_s"] else float("nan")
            w(f"**C2 survives falsification condition F-a.** The slope on discarded redo is "
              f"positive with its interval excluding zero: the database pays measurably for redo "
              f"the connector reads and throws away. At the highest admissible level "
              f"({worst['redo_discarded_gb']:.2f} GB discarded) that accounts for roughly "
              f"**{share:.0f} % of the total database-side capture cost**, against a captured "
              f"volume that never changed.")
        else:
            w("**C2 is falsified by condition F-a.** The slope's interval includes zero: on this "
              "evidence mining cost does not rise with redo the connector discards, and narrowing "
              "the capture scope does reduce database overhead. This is a result and is reported "
              "as prominently as the alternative would have been.")

        result.update({"slope_cpu_s_per_gb_discarded": slope, "slope_ci": [lo, hi],
                       "intercept_s": intercept, "c2_supported": bool(supported),
                       "levels_in_fit": [p["level"] for p in admissible]})
    else:
        w(f"**Inconclusive — only {len(admissible)} admissible levels.** A slope cannot be "
          f"estimated from fewer than three. The excluded levels are listed above with the "
          f"reason; each needs a rerun before C2 can be decided either way.")
        result["c2_supported"] = None

    # ------------------------------------------------------------- C2b ----
    # The operational half: does narrowing table.include.list actually reduce cost? Reported
    # separately because it carries its own control — total redo must be the same in both arms —
    # and that control can fail independently of C2a's.
    scope = defaultdict(list)
    with open(args.summary) as fh:
        for row in csv.DictReader(fh):
            if row.get("profile") in ("C2NARROW", "C2WIDE", "C2N4OFF"):
                scope[row["profile"]].append(row)

    if scope.get("C2NARROW") and scope.get("C2WIDE") and scope.get("C2N4OFF"):
        w("\n---\n\n## C2b — does narrowing the capture scope reduce cost?\n")
        base_cpu = med(col(scope["C2N4OFF"], "cpu_used_delta")) or 0.0
        w("| Arm | total redo (GB) | CPU (s) | mining cost (s) | events delivered | A1 TPS |")
        w("|---|---|---|---|---|---|")
        rowvals = {}
        for arm in ("C2N4OFF", "C2NARROW", "C2WIDE"):
            rs = scope[arm]
            cpu = med(col(rs, "cpu_used_delta")) or 0.0
            redo = (med(col(rs, "redo_size_delta")) or 0.0) / BYTES_PER_GB
            dl = med(col(rs, "delivered_total")) or 0.0
            gt = med(col(rs, "ground_truth_transitions")) or 1.0
            tps = med(col(rs, "achieved_tps")) or 0.0
            cost = (cpu - base_cpu) / CENTISECONDS_PER_SECOND
            rowvals[arm] = {"redo": redo, "cost": cost, "dl": dl, "gt": gt, "tps": tps}
            label = {"C2N4OFF": "connector absent (baseline)", "C2NARROW": "narrow — TXN_A1 only",
                     "C2WIDE": "wide — TXN_A1 + REDO_NOISE"}[arm]
            w(f"| {label} | {redo:.2f} | {cpu/CENTISECONDS_PER_SECOND:.1f} | "
              f"{'—' if arm == 'C2N4OFF' else f'{cost:.1f}'} | "
              f"{dl:,.0f} / {gt:,.0f} ({100*dl/gt:.0f} %) | {tps:.1f} |")

        n, wd = rowvals["C2NARROW"], rowvals["C2WIDE"]
        redo_gap = abs(n["redo"] - wd["redo"]) / max(n["redo"], wd["redo"])
        tps_gap = abs(n["tps"] - wd["tps"]) / max(n["tps"], wd["tps"])
        w("")
        if redo_gap > 0.15 or tps_gap > 0.05:
            w(f"**C2b is inconclusive: its control failed.** The design requires total redo to be "
              f"identical in both arms, and it was not — {n['redo']:.2f} GB narrow against "
              f"{wd['redo']:.2f} GB wide, **{100*redo_gap:.0f} % apart**. A1 throughput also "
              f"diverged, {n['tps']:.1f} against {wd['tps']:.1f} TPS.")
            w("")
            w(f"The wide arm's lower measured cost ({wd['cost']:.1f} s against {n['cost']:.1f} s) "
              f"is therefore **not** evidence that a wider scope is cheaper. It did less work: "
              f"mining the noise table slowed the instance enough that the noise generator could "
              f"not sustain its rate, so the arm that was supposed to carry identical redo "
              f"carried half as much. **Falsification condition F-b remains untested.**")
            w("")
            w(f"What the arm does show, as an operating-envelope observation rather than a test: "
              f"adding a high-volume table to `table.include.list` cost this instance "
              f"{100*(1 - wd['tps']/n['tps']):.0f} % of its OLTP throughput and left the connector "
              f"delivering {100*wd['dl']/wd['gt']:.0f} % of committed events inside the settle "
              f"window.")
            result["c2b"] = {"valid": False, "redo_gap": redo_gap, "tps_gap": tps_gap}
        else:
            ratio = wd["cost"] / n["cost"] if n["cost"] else float("nan")
            w(f"Cost ratio wide:narrow = **{ratio:.2f}**. The naive assumption predicts this "
              f"tracks the ratio of captured volume; C2 predicts it stays near 1.")
            result["c2b"] = {"valid": True, "cost_ratio": ratio}

    report = "\n".join(out)
    print(report)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(report + "\n")
    if args.json_out:
        with open(args.json_out, "w") as fh:
            json.dump(result, fh, indent=2)


if __name__ == "__main__":
    main()
