# Experiment C2 — Does LogMiner Overhead Track Total Redo or Captured Redo?

## Chapter 6 material · design fixed before any data is collected

**Status: RUN AND ANALYSED, 10 September 2026.** C2a supports the claim; C2b's control failed
and F-b remains untested. Full results in `results/c2-report.md`.

| | |
|---|---|
| **C2a — does cost rise with redo the connector discards?** | **C2 survives F-a.** Slope **13.01 CPU-seconds per GB of discarded redo**, 95 % bootstrap CI **5.86 – 18.62**, interval excluding zero. Intercept 5.02 s. Four of five levels admissible. At the highest admissible level, **79 % of the database-side capture cost is spent on redo that never becomes an event**, against a captured volume that never changed. |
| **C2b — does narrowing the scope reduce cost?** | **Inconclusive.** Total redo was 52 % apart between the two arms and A1 throughput diverged, so the control failed. F-b is untested. |

The fit is close to linear: predicted 24.1 s at level 3 against 24.3 measured, 9.7 against 11.2 at
level 1, 14.5 against 13.4 at level 2.

**Level 4 was excluded** by the pre-registered admissibility rule: at 2.85 GB of discarded redo the
connector delivered only 30 % of committed events inside the settle window. That exclusion is
itself an operating-envelope observation — somewhere between 1.5 and 2.9 GB of uncaptured redo per
180 s window, this connector stops keeping up.

### What it took to get a valid measurement

Three prior attempts produced data that looked analysable and was not. Each is recorded in the
harness documentation because the failures are instructive:

1. **The workload never ran.** C2's per-cell profile labels were also the k6 scenario selector, so
   k6 refused to start and 35 cells were written with zero transitions and no complaint.
2. **The drain stopped early.** A sink sitting at zero counts as "stable", so runs exported an
   empty topic and scored every event as lost.
3. **The two arms were not comparable.** The connector-absent arm had no sink to fill, never
   satisfied the non-empty drain condition, and therefore always ran to the full settle timeout —
   about 100 extra seconds during which the noise generator kept writing. The arms ended 36–40 %
   apart in total redo, and the inflated baseline CPU biased the result *against* C2.

The fix for the third was to separate the **measurement window** from the **drain wait**: counters
are now snapshotted after a fixed interval identical in both arms, and the variable drain runs
afterwards purely so the export is complete. The arms now differ by 0–2 % in total redo.

**A fourth failure was in the analysis, not the experiment.** Captured redo was computed as
`redo_bytes_per_transition × transitions`, and that column is itself `redo_total / transitions`, so
the product returned `redo_total` exactly. The two regressors were identical, the fit was
unidentifiable, and it reported C2 **falsified** on coefficients of −1217 and +1224 that cancel.
The design's own two-model comparison was also wrong for C2a, which holds captured redo constant
by construction: the correct test is the sign of a single slope. Both are corrected.

---

## 1. The claim, and why it is the most valuable one in the thesis

> **C2.** LogMiner-based CDC overhead scales with the **total redo volume of the database**, not
> with the write volume of the captured tables — so narrowing `table.include.list` does **not**
> proportionally reduce database overhead.

The practitioner assumption is the opposite. "We only capture three tables, so CDC costs us
almost nothing" is a sentence heard in every CDC adoption discussion, and it is the sentence
that decides whether a bank puts a capture process on its core banking instance. If C2 holds,
that reasoning is wrong in a way that matters: a bank that narrows its capture scope to reduce
risk has reduced the *output* of the pipeline while paying nearly the same *input* cost.

The mechanism, if the claim is true, is straightforward. LogMiner reads redo records
sequentially over an SCN range and reconstructs statements from them; the connector's
`table.include.list` is applied **after** that reconstruction, as a filter on the result set.
Scanning is therefore proportional to everything written to the database in the interval, and
filtering only decides how much of that scan produces output.

Everything built so far in this thesis measures C1 (loss under faults) and C3 (the decision
model). C2 has had no experiment behind it. This document is that experiment.

---

## 2. What would falsify it — stated before the data exists

Pre-committing to the falsification condition is the difference between a test and an
illustration, and it is the first thing a examiner should be able to check.

C2 is **falsified** if either of the following holds:

* **F-a.** In the cost model of §6, the fitted coefficient on *total* redo is not significantly
  greater than zero — that is, mining cost is explained by captured redo alone.
* **F-b.** Widening the capture scope from one table to a scope covering ~90 % of the
  instance's redo raises the database-side cost by approximately the same ratio as the captured
  volume, i.e. the cost is proportional to what is captured.

C2 is **supported** if mining cost rises materially with uncaptured redo at a constant captured
write rate, and if the captured-redo coefficient explains only a minority of the total cost.

An outcome in between — a real but sub-proportional dependence on scope — is the most likely
result and is still publishable, provided the *magnitude* is reported rather than the direction
alone. §6 therefore reports a coefficient with an interval, not a yes/no verdict.

---

## 3. Design

Two sub-experiments. They are the two halves of the claim and neither is sufficient alone.

### C2a — vary uncaptured redo, hold captured writes constant

The positive half: does cost rise with redo that the connector will discard?

| | |
|---|---|
| **Held constant** | A1 workload at 50 TPS; capture scope = `OBSV.TXN_A1` only; ALL-column supplemental logging on `TXN_A1`; `log.mining.strategy=online_catalog`; run duration 180 s |
| **Manipulated** | `N` — the rate of writes into `REDO_NOISE`, a table **not** in `table.include.list`. Five levels, N0 … N4 |
| **Also manipulated** | `C` — connector absent / connector running. Both states at every level of `N` |
| **Repetitions** | 3 per (N, C) cell → 5 × 2 × 3 = **30 runs** |

### C2b — vary capture scope, hold total redo constant

The operational half: does the DBA's actual lever work?

| | |
|---|---|
| **Held constant** | A1 workload at 50 TPS; noise fixed at N4; run duration 180 s |
| **Manipulated** | scope ∈ { narrow = `TXN_A1`, wide = `TXN_A1, REDO_NOISE` } |
| **Repetitions** | 3 per scope → **6 runs**. The connector-absent baseline at N4 is reused from C2a |

Total: **36 runs, ≈ 3.6 hours** of unattended machine time.

---

## 4. The dependent variable, and why it is a difference of differences

"CDC overhead" is measured here as **Oracle-side CPU**, not connector CPU. The claim is about
what capture costs *the database*, which is the quantity a bank cares about and the quantity
that decides whether capture is allowed on a core instance at all. Connector-side CPU is
recorded as a secondary variable but is not the test: it scales with events *produced*, which
is exactly the thing C2 says is not the driver.

Attributing CPU to the mining session directly is unreliable, because Debezium's LogMiner
session is torn down and recreated between mining iterations, so a per-session counter loses
whatever it accumulated before the last teardown. Instead the design takes a **difference of
differences** at each noise level:

```
mining_cost(N)  =  CPU_instance(N, connector ON)  −  CPU_instance(N, connector OFF)
```

Both terms are measured with the instrument the harness already uses — `V$SYSSTAT` deltas
across the run — and the workload is byte-for-byte identical in the two conditions, because the
connector does not touch the application. Everything the two conditions share, including the
noise generator's own CPU and the cost of supplemental logging, cancels in the subtraction.

**Supplemental logging must be enabled in the connector-OFF condition too.** It is a property of
the table, not of the connector: it changes how much redo Oracle *writes*, not how much anyone
*reads*. Leaving it off in the baseline would put the supplemental-logging redo cost inside the
measured "mining cost" and inflate every point in the same direction. The harness's
`--no-connector` flag exists exactly so that a `CDC` run can be executed with the capture
configuration intact and the connector absent.

### Variables recorded per run

| Variable | Source | Role |
|---|---|---|
| `CPU used by this session` (instance-wide) | `V$SYSSTAT` delta | **primary DV**, via the difference above |
| `DB time` | `V$SYSSTAT` delta | secondary DV; catches cost that is wait rather than CPU |
| `redo size` | `V$SYSSTAT` delta | **the independent variable, measured rather than assumed** |
| redo of captured tables | derived: `BASELINE_GT` redo/transition × transitions | the competing explanatory variable |
| log switches | `V$LOG_HISTORY` count in the window | mechanism check — see §7 |
| `physical reads` | `V$SYSSTAT` delta | mining from archived logs reads from disk |
| `MilliSecondsBehindSource` | Connect JMX → Prometheus | does the connector fall behind as noise rises? |
| events produced | topic end offsets | **manipulation check** — must be constant across N |
| achieved A1 TPS | k6 | **manipulation check** — must be constant across N |
| connector process CPU | Connect JMX | secondary; expected to track output, not input |

---

## 5. The noise generator

`REDO_NOISE` is a deliberately wide table written by `PKG_REDO_NOISE.run(duration, rows_per_second)`,
which paces itself in one-second batches for the duration of the run.

Three properties matter and each is a design decision, not an accident:

**It is paced, not bursty.** A single large batch would produce a redo *spike* and a log-switch
storm rather than a sustained *level*, and the connector's adaptive batch sizing would respond
to the transient rather than to the level being tested. The generator sleeps between batches to
hold a steady rate.

**It writes wide rows and then updates them.** Redo volume per row, not row count, is the
quantity being manipulated. Updates are included because an update writes both the change vector
and — under the table's logging attributes — potentially more, which makes the rate tunable over
a wide range without an absurd number of rows.

**It is never in `table.include.list` during C2a, and carries no supplemental logging there.**
If it were captured, or logged ALL-column, the noise would stop being uncaptured and the
experiment would measure nothing. `ModeActivator`'s existing per-mode supplemental-logging switch
already enforces "log exactly the captured table and nothing else", which is the invariant this
experiment depends on.

**Calibration.** Levels N0…N4 are expressed in redo bytes per second, not rows per second,
because rows are not the unit of interest. A calibration run measures the redo produced per
noise row on this instance and the levels are then set to span roughly 0×, 1×, 2×, 4× and 8× the
redo generated by the A1 workload itself. The calibration figures are recorded in the results,
so the levels are reproducible.

---

## 6. Analysis

The two candidate models are fitted to the same data and compared:

```
naive model   mining_cost  =  b · redo_captured
C2 model      mining_cost  =  a · redo_total  +  b · redo_captured
```

Reported as **CPU-seconds per gigabyte of redo**, with `a` the cost of redo the connector reads
and discards, and `b` the additional cost of redo it converts into events.

Three quantities carry the result:

1. **`a`, with a bootstrap confidence interval.** The headline. If its interval excludes zero,
   the scan cost is real and C2 survives F-a.
2. **The discard fraction** — `a · redo_discarded / mining_cost` — the share of the database's
   capture cost spent on redo that never becomes an event. This is the number a bank would
   quote, and the one worth putting in the abstract.
3. **The scope elasticity from C2b** — the ratio of the proportional change in cost to the
   proportional change in captured volume. The naive assumption predicts ≈ 1. C2 predicts ≪ 1.

Ordinary least squares is used for the point estimates and a bootstrap over runs for the
intervals; with three repetitions at five levels the residual degrees of freedom are small and a
normal-theory interval would overstate precision. The same discipline as the rest of the thesis
applies: report the interval, not the point alone.

### The analysis was validated before it was used

`harness/c2-analyze.py` was run against two synthetic datasets built with **known** coefficients,
one in which scanning dominates and one in which only captured redo matters. It recovered both:

| Injected | Recovered `a` | Recovered `b` | Verdict reached |
|---|---|---|---|
| `a = 40`, `b = 5` (C2 true) | 40.01, CI 39.93 – 40.18 | 5.09 | supports C2, discard fraction 87 % |
| `a = 0`, `b = 400` (C2 false) | 0.04, CI −0.09 – 0.09 | 399.30 | **falsifies C2** |

This matters because the instrument has to be able to return *both* answers. An analysis that
can only confirm the hypothesis it was written for is not a test, and after finding three
defects in this harness that produced better-looking results than the truth, taking that on
trust would be inconsistent with the rest of the work.

---

## 7. Threats to validity, and what is done about each

| Threat | Why it matters | Control |
|---|---|---|
| **The noise starves the A1 workload.** Heavy uncaptured writes slow the OLTP path, so captured events fall and the comparison confounds. | Would invalidate every point at high `N` | Achieved A1 TPS and captured event count are manipulation checks. Any level at which A1 throughput degrades by more than 5 % is reported and excluded from the fit rather than quietly retained |
| **Log switches confound with total redo.** More redo means more frequent switches, and mining an archived log differs from mining an online one. | This is partly *mechanism* and partly *nuisance* | Log switches are counted per run and reported alongside the fit, so a reader can see whether the effect survives at constant switch count. Not controlled away, because in production redo volume and switch frequency genuinely co-vary |
| **Debezium's adaptive batch sizing responds to lag.** The connector changes its own query pattern as it falls behind. | The independent variable could be partly endogenous | `MilliSecondsBehindSource` is recorded per run. If the connector never falls materially behind, adaptation is not in play; if it does, that is itself a finding about the operating envelope |
| **The connector-OFF baseline drifts** between its run and the paired ON run. | The subtraction assumes the two are comparable | The two states at each level are run adjacently within a repetition, and repetitions are interleaved and rotated, exactly as in the main matrix |
| **Single-instance, containerised Oracle.** | External validity | Stated as a bound, as everywhere else in this thesis. The claim is about the *shape* of the dependence, which is a property of how LogMiner reads redo, not of the hardware |
| **`online_catalog` strategy only.** | The result may not generalise to the other mining strategies | Stated as a scope limit. A second strategy is future work, not a gap in this design |

---

## 8. Why this design and not the obvious one

The obvious experiment is: register the connector with a narrow scope, then with a wide scope,
and compare CPU. It is the wrong experiment, for two reasons.

**It confounds scanning with conversion.** A wide scope produces far more events, so its
connector does far more serialization, network and Kafka work. Any cost difference is then
attributable to output volume, which is not what C2 is about. C2a avoids this entirely by
holding the captured set fixed and varying only what is discarded — the one manipulation that
changes scan input without changing output.

**It has no baseline.** Without the connector-OFF condition there is nothing to subtract, and
the measured CPU includes the workload, the noise generator and the instance's background
activity. The difference-of-differences is what turns a system-wide counter into an
attributable quantity.

C2b is retained *despite* the confound because it is the operationally meaningful form of the
question — scope is the lever a DBA actually has — and because C2a supplies the interpretation
that makes its result readable.

---

## 9. Files

| Path | Purpose |
|---|---|
| `src/main/resources/db/migration/V10__redo_noise.sql` | `REDO_NOISE` table and `PKG_REDO_NOISE` |
| `docker/connect/connectors/cdc-wide.json.tmpl` | Wide-scope connector for C2b |
| `scripts/run-c2.sh` | Runs both sub-experiments; resumable, interleaved |
| `harness/c2-analyze.py` | Fits both models, bootstraps `a`, reports the discard fraction. Validated against synthetic data with known coefficients in both directions |
| `harness/sql/noise-run.sql`, `noise-stop.sql`, `noise-calibrate.sql` | Start, kill and calibrate the generator |
| `scripts/run-experiment.sh --no-connector` | The connector-absent arm, capture configuration intact |
| `results/c2/` | One directory per run, one row per run in `results/c2-summary.csv` |
