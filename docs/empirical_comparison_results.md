# Empirical Comparison of Event-Capture Approaches

## Chapter 6 · results table for Oracle-backed A1 transaction processing

**Measurement basis.** 175 archived experimental cells: 40 steady-state, 63 fault, 36 corrected
fault reruns, 36 for experiment C2. Steady state is eight modes, five repetitions each, 50 TPS for 120 s per cell, repetitions
interleaved and mode order rotated so that no mode is confounded with the time of day it ran at.
Roughly **90 000 state transitions per mode**, ~720 000 in total. Every figure below is a median
across five runs unless stated otherwise. Raw data: `results/summary.csv`; full statistics:
`results/aggregate-P1.md`.

**Reference conditions.** Oracle 26ai Free 23.26.3 in ARCHIVELOG with FORCE LOGGING, Kafka 4.1
KRaft with RF=3 and `min.insync.replicas=2`, Debezium 3.5.2, Spring Boot 4.1.1 / Java 21, single
container host. All comparisons are **relative between modes under identical conditions** and are
not predictions of production behaviour on RAC or Exadata.

**Two baselines, not one.** `OFF` runs the workload with no instrumentation at all;
`BASELINE_GT` adds only the ground-truth trigger that the measurement itself needs. Every cost
below is reported against `BASELINE_GT`, so the measuring apparatus's own overhead is quantified
rather than hidden inside each result. The apparatus costs +0.27 ms at HTTP p95 and nothing
detectable in redo.

---

## 1. The comparison matrix

| Metric | **A1 · Internal PL/SQL (AQ)** | **A2 · Application Outbox (B3)** | **A3 · Log-based CDC (Debezium)** | **HYBRID · Outbox + Debezium** |
|---|---|---|---|---|
| **End-to-end latency, p50** | **6 ms** | 128 ms | 3 362 ms | 3 186 ms |
| **End-to-end latency, p95** | 13 ms | 231 ms | 6 751 ms | 5 804 ms |
| **End-to-end latency, p99** | 1 017 ms | 1 279 ms | 8 177 ms | 7 539 ms |
| **Redo amplification** *(bytes/transition vs control)* | 10 515 · **+171.4 %** | 8 153 · **+110.4 %** | 3 901 · **+0.7 %** | 7 128 · **+84.0 %** |
| *— statistical significance (exact permutation)* | p = 0.0079 | p = 0.0079 | p = 0.0952 *(n.s.)* | p = 0.0079 |
| **OLTP impact, HTTP p95 delta** | +1.55 ms | +1.64 ms | **−0.18 ms** | +2.37 ms |
| *— as % of control (5.40 ms)* | +28.6 % | +30.4 % | −3.3 % *(n.s.)* | +43.8 % |
| **Extra database commits** *(per 120 s run)* | +6 758 | +531 | +101 | +99 |
| **Loss rate, clean running** | 0 observed · **< 33.5 ppm** | 0 observed · **< 33.3 ppm** | 0 observed · **< 33.3 ppm** | 0 observed · **< 33.3 ppm** |
| **Loss rate, writer bypassing the app (F11)** | **0 %** | **69.0 %** | **0 %** | **69.0 %** ¹ |
| **Loss rate, same writer using the outbox contract (F11B)** | n/a | **0 %** | n/a | **0 %** |
| **Loss rate, process killed under load (F1R)** | **0 / 0 / 0** | **0 / 0 / 0** | **0 / 0 / 0** | **0 / 0 / 0** ² |
| **Loss rate, broker outage 90 s (F2)** | 0 % | 0 % | 0 % | 0 % |
| **Loss rate, archives purged, 10 log switches (F4R)** | n/a | n/a | **0 %** | **0 %** |
| **Loss rate, transaction held 240 s past a 180 s retention (F5R)** | n/a | n/a | **0 %** | **0 %** |
| **Availability coupling (F8)** | **40.0 % of payments failed** | none | none | none |
| **Database CPU per GB of *discarded* redo (C2a)** | n/a | n/a | **13.0 CPU-s** | **13.0 CPU-s** |
| **Sustained throughput** | 45.6 tps | 45.6 tps | 45.6 tps | 45.6 tps |
| **Throughput ceiling** | *not measured* ³ | *not measured* ³ | *not measured* ³ | *not measured* ³ |
| **Implementation volume** *(measured LOC)* | 591 | 468 | **175** | 253 |
| **Added application dependencies** | 2 (`aqapi-jakarta`, `spring-jms`) | 0 | 0 | 0 |
| **Required infrastructure** | none beyond Oracle | none beyond Oracle | Kafka Connect + Debezium | Kafka Connect + Debezium |
| **Environment defects encountered** ⁴ | 6 | 3 | 5 | 4 |
| **LOE / complexity** *(structured estimate)* | **High** | **Medium** | **Low-Medium** | **Medium** |

¹ The hybrid failed F11 *identically to the plain wrapper*, and this was not predicted. F11B then
showed both recovering complete coverage once the batch writes through the shared
`EMIT_A1_EVENT` contract. See §3.3 — the pair is the most consequential finding in the table.

² The naive wrapper variants, which are not in this table, are the ones that lose here:
`WRAPPER_B1` lost events in two of three repetitions and `WRAPPER_B2` in all three, while the
four patterns above lost nothing in any of twelve. That contrast is claim C1.

³ **Profile P2 (ramp to saturation) has not been run.** No mode was the bottleneck at the 50 TPS
operating point: all four sustained 45.6 tps and none showed throughput degradation. The ceiling
is genuinely unknown and is not estimated here. What *is* known is that `WRAPPER_B2` — the naive
after-commit variant, not in this table — was already the binding constraint at 50 TPS with an
HTTP p99 of 8 s, which is why 50 TPS rather than 200 TPS was chosen as the operating point.

⁴ Reproducible deviations from documented behaviour encountered while building each approach,
from `docs/implementation-environment.md`. Reported because they are a real component of level of
effort that a line count does not capture.

### 1.1 How each metric was measured

| Metric | Instrument | Note |
|---|---|---|
| End-to-end latency | Kafka record timestamp − ground-truth commit time | `analyze.py`; ground truth written by a trigger inside the business transaction |
| Redo amplification | `V$SYSSTAT` `redo size` delta ÷ committed transitions | `OracleMetricsBinder` + `snapshot-stats.sql` before/after each run |
| OLTP impact | k6 `http_req_duration` p95 at the service boundary | p95 rather than p99 — see §2.4 |
| Commits | `V$SYSSTAT` `user commits` delta | |
| Loss rate | Reconciliation on `(txn_id, new_status)` against `GROUND_TRUTH` | The only key that exists in all eight modes |
| Significance | Exact two-sided permutation test on Mann-Whitney U | At n = 5 the smallest attainable p is 2/252 = **0.0079** |

---

## 2. Scientific insights and key takeaways

### 2.1 Commit latency versus delivery speed: the trade-off is real and it is a 560× spread

The four pipelines deliver the same events from the same workload, and their median end-to-end
latency spans **6 ms to 3 362 ms — a factor of 560**.

The ordering is not incidental and will not move with more repetitions, because it follows from
*where the mechanism sits relative to the commit*:

* **AQ is notified.** The bridge blocks in `DBMS_AQ.DEQUEUE` and the enqueue wakes it. There is no
  polling interval to wait through, and the message becomes visible exactly at commit because it
  is enqueued with `visibility => ON_COMMIT`. Median 6 ms.
* **The outbox relay asks repeatedly.** A row waits on average half a poll interval before anyone
  looks at it. At the configured 200 ms interval that is 100 ms of expected delay before
  publication even begins — and the measured 128 ms median is that plus the publish. Predictable,
  and directly tunable by the interval at the cost of more polling load.
* **Both Debezium pipelines wait for the mining cycle.** LogMiner is itself a poll, and a much
  slower one than 200 ms. Median 3.2–3.4 s at Debezium's default cadence.

**The inverse relationship is the finding.** Redo amplification runs in the opposite direction to
latency: AQ is the fastest deliverer and the most expensive writer (+171 %), CDC is the slowest
deliverer and effectively free to the writer (+0.7 %, not statistically distinguishable from the
control). Speed of delivery is bought with work done inside the transaction.

**But CDC's cost is not zero — it is merely moved.** Experiment C2 varied the redo the connector
discards while holding the captured workload constant, and measured database CPU as a difference
against the same run with the connector absent. Mining cost rises at **13.0 CPU-seconds per
gigabyte of discarded redo** (95 % bootstrap CI 5.86 – 18.62, excluding zero), against a captured
volume that never changed. At the highest admissible level, **79 % of the database-side capture
cost was spent reading redo that never became an event.** Approach 3 is cheap in the transaction
and expensive in the instance — a different budget line, not an absent one. §2.5.

A prediction of this thesis's own analysis document was refuted here and has been retracted: it
stated that relaying the outbox with Debezium "cuts end-to-end latency". It does not. It removes
the polling query **from the database**, which is a genuine operational benefit, but the events
arrive 25× later. The hybrid's case rests on coverage and on database protection, not on speed.

### 2.2 The silent failure in pure CDC: the right number of empty events

**This is the strongest methodological result in the thesis, and it is a warning about how CDC
pipelines are normally monitored.**

The first CDC run published **9 003 messages for 9 003 committed state transitions**. Counts
matched exactly. Every message was well-formed JSON. The connector reported `RUNNING` throughout,
its lag metrics were flat, and it logged no warning of any kind.

Two thirds of those messages looked like this:

```json
{ "TXN_ID": "0", "TXN_REF": "", "AMOUNT": "0.0000", "STATUS": "VALIDATED" }
```

`TXN_A1` carried only the database's **minimal** supplemental logging. The redo record for an
`UPDATE` then contains the changed columns and the row identifier and nothing more, and Debezium
fills what the redo does not supply with type defaults. `INSERT` events were complete; every
`UPDATE` event was hollow.

**Every count-based validation passes perfectly in this state** — and count-based validation is
what most production CDC deployments actually have. Message counts match. No message is
malformed. No message is missing. Connector health is green. Lag is zero. A dashboard built on
those signals reports a fully healthy pipeline that is delivering two-thirds unusable events.

Only reconciliation against an **independent ground truth on a semantic key** exposes it. That is
the justification for this thesis's entire measurement design, and it generalises past this
experiment:

> **Counting events does not measure an event pipeline.** A pipeline can deliver exactly the
> right number of structurally valid, semantically empty messages, and every conventional health
> signal will report success.

The remedy is `ALTER TABLE … ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS` on each captured table.
After it, the same run reconciled 9 003 / 9 003 with zero loss, zero phantoms and zero ordering
violations.

**Operational consequence, and a cost attributable to Approach 3.** ALL-column supplemental
logging makes Oracle write the whole row to redo on every UPDATE, whether or not anyone is mining
it. In this study it is therefore switched **per mode** rather than left on: enabling it once on
`TXN_A1` and leaving it there would have charged Approach 3's redo cost to every other approach,
including the baselines, and would have understated how much CDC costs relative to the
alternatives.

### 2.3 Why the hybrid balances database protection against decoupling — and the condition it depends on

The hybrid writes the event into an outbox table inside the business transaction, and lets
Debezium relay it from the redo log. Measured, that buys:

* **No dual write.** The event and the business fact share one commit, so there is no window in
  which the fact is durable and the event is not. Zero loss observed across ~90 000 transitions
  and through a 90-second broker outage.
* **No polling load on the OLTP instance.** The outbox relay's claim query disappears entirely;
  Debezium reads the redo log instead. Visible in the commit counts: +99 extra commits against
  the outbox relay's +531, and against AQ's +6 758.
* **Lower redo than the alternatives that also write in-transaction** — +84.0 % against the
  outbox relay's +110.4 % and AQ's +171.4 %. The relay's `UPDATE … SET PUBLISHED_AT` never
  happens, because Debezium does not mark rows published.
* **No availability coupling.** A defect in the capture path cannot fail a payment, because the
  capture path is a plain `INSERT` into a table the application already writes.

**The condition, measured.** Fault F11 drives an end-of-day PL/SQL batch that writes A1
transactions directly, bypassing the application. Three repetitions, ~87 000 transitions each:

| Mode | Missing | Loss rate |
|---|---|---|
| `AQ` | 0 / 86 990 | **0 %** |
| `CDC` | 0 / 86 994 | **0 %** |
| `WRAPPER_B3` | 59 983 / 86 984 | **69.0 %** |
| `HYBRID` | 59 990 / 86 991 | **69.0 %** |

**The hybrid failed identically to the plain wrapper.** The analysis document argues that the
hybrid achieves complete writer coverage because the Spring writer and legacy PL/SQL batches
write through the same `EMIT_A1_EVENT` contract. They do — *if the legacy writer is modified to
call it*. The batch generator models an **unmodified** legacy writer and does not.

So the hybrid's writer coverage is not a property of the architecture. It is a property of an
organisation's willingness and ability to modify every writer that touches the table. Where that
cannot be guaranteed — which in a core banking system with decades of batch jobs is the normal
case — **only the trigger and the redo log see everything**.

A rerun is queued in which the batch *does* honour the contract, so the assumption is measured on
both sides rather than only on the side that makes it look bad.

### 2.5 CDC's cost scales with what it scans, not with what it captures — claim C2

The practitioner assumption is that narrowing `table.include.list` narrows the cost: "we only
capture three tables, so CDC costs us almost nothing." That sentence decides whether a bank
allows a capture process on its core instance.

**Experiment C2a tested it, with the falsification condition fixed before any data existed.** The
A1 workload and the capture scope were held constant while the redo written to a table *outside*
the include list was varied across five levels; each level was run with the connector present and
absent, and mining cost taken as the difference. Because captured redo is constant by design, the
two hypotheses differ in the sign of one slope: the naive assumption predicts a flat cost, C2
predicts a rising one.

| Discarded redo | Mining cost |
|---|---|
| 0.000 GB | 4.5 s |
| 0.364 GB | 11.2 s |
| 0.728 GB | 13.4 s |
| 1.469 GB | 24.3 s |

Fitted slope **13.01 CPU-seconds per GB discarded**, 95 % CI **5.86 – 18.62**, intercept 5.02 s.
The fit is close to linear — 24.1 s predicted against 24.3 measured at the top level. **C2 survives
its falsification condition.**

The mechanism is straightforward once measured: LogMiner reads redo records sequentially over an
SCN range and reconstructs statements from them, and `table.include.list` is applied *after* that
reconstruction, as a filter on the result. Scanning is proportional to everything the database
wrote; filtering only decides how much of that scan produces output.

**Two limits are stated rather than smoothed over.** A fifth noise level was excluded by the
pre-registered admissibility rule: at 2.85 GB discarded the connector delivered only 30 % of
committed events inside the settle window — an operating-envelope observation in its own right.
And **C2b, which would have tested the scope lever directly, is inconclusive**: mining the extra
table slowed the instance enough that the noise generator could not sustain its rate, so the two
arms ended 52 % apart in total redo and the control failed. Falsification condition F-b remains
untested.

### 2.4 Two measurement cautions that belong in the results chapter

**HTTP p99 is not usable on this rig.** The uninstrumented `OFF` control — which does no
instrumentation work at all — produced p99 values of 6.7, 8.9, 10.2, 197.3 and 278.7 ms across
five identical runs: a 40× spread. Any p99 difference between modes smaller than that is
environment noise being read as a mechanism property. p95 is stable across repetitions and is
used throughout; the p99 instability is reported as a limitation, not as a finding.

**Zero loss is reported as an upper bound, never as zero.** Claiming `LR = 0` from a finite sample
is unfalsifiable. With ~90 000 transitions and no loss observed, the Rule of Three gives
`LR < 33.3 ppm at 95 % confidence`. Pooling across the five repetitions before bounding is what
tightens the bound from 167 ppm at one run to 33 ppm at five.

---

## 3. Recommendation for a high-availability A1 workflow

| Constraint | Recommended | Why |
|---|---|---|
| Every writer reaches the table through the application, and the source is modifiable | **HYBRID** | No dual write, no polling load, lowest in-transaction cost of the atomic options, no availability coupling |
| Writers exist that bypass the application and cannot be modified | **CDC**, or **AQ** where sub-100 ms latency is also required | The only two that observed 100 % of the bypassing batch |
| Sub-100 ms end-to-end latency is a hard requirement | **AQ** | 6 ms median. Accepted cost: +171 % redo, and a capture defect can fail payments (F8) |
| Database overhead must be near zero | **CDC** | +0.7 % redo and −0.18 ms HTTP p95, neither distinguishable from the uninstrumented control |
| Cannot introduce Kafka Connect / Debezium into the estate | **Outbox (B3)** | 468 lines, no added dependencies, no new infrastructure. Costs +110 % redo and a 200 ms polling delay |

**The single most important trade-off in the table:** availability coupling. Approach 1 is the
only mechanism where a defect in the observability path **stopped 40 % of payments** (fault F8).
For a core banking system that is not a performance characteristic — it is a category of outage
that the other three approaches structurally cannot produce.

---

## 4. Scope and validity

* All figures are **relative comparisons between modes under identical conditions** in a
  containerised single-instance environment. They are not predictions for RAC or Exadata.
* Loss rates with no observed loss are **one-sided upper bounds**, not zeroes.
* **LOE is a structured estimate.** Its measurable components — implementation volume, added
  dependencies, required infrastructure, environment defects encountered — are given in the table
  so the estimate can be checked rather than taken on trust. The ordinal grade is judgement.
* **Throughput ceilings are not measured.** Profile P2 has not been run.
* The evaluation covers **event generation**, not event consumption or downstream processing.
* Fault cases F4 and F5 were corrected and rerun. Both **refute** the predictions made for them:
  purging every archive after ten forced log switches caused no loss, and a transaction held 240 s
  against a 180 s configured retention was not discarded. Those refutations hold at the tested
  outage and hold lengths, not generally. Details in `docs/fault-matrix-results.md`.
* **C2b is inconclusive** — its control failed. Only C2a's result is claimed.
* Of seven statements the fault matrix set out to test, three are established, one is supported
  with a stated statistical limitation, and **three are refuted** — two of them contradicting
  predictions this thesis made before any of it was built.

---

## 5. Provenance

| Artefact | Path |
|---|---|
| Raw per-run data | `results/summary.csv` |
| Full statistics, Phase A | `results/aggregate-P1.md` |
| Fault matrix analysis | `docs/fault-matrix-results.md` |
| Per-run archives (ground truth, topic export, DB counters, k6) | `results/<run-id>/` |
| Harness methodology | `docs/experiment-harness.md` |
| Environment and its 23 documented defects | `docs/implementation-environment.md` |
| Reconciliation and statistics code | `harness/analyze.py`, `harness/aggregate.py` |

---

## 6. Appendix — exact experimental setup and configuration

Requested detail: every parameter below is read from the running instance or the checked-in
configuration that produced §1's numbers, not reconstructed from memory. Where a value is an
image default rather than a deliberate tuning choice, that is stated rather than left implicit.

### 6.1 Harness parameters (the run that produced §1)

| Parameter | Value | Source |
|---|---|---|
| Repetitions per mode | 5 | `scripts/run-matrix.sh`, `REPS` |
| Target rate | 50 TPS | `scripts/run-matrix.sh`, `TPS` |
| Steady-state duration | 120 s | `scripts/run-matrix.sh`, `DURATION` |
| Fault-case repetitions | 3 | `FAULT_REPS` |
| Fault-case duration | 180 s | `FAULT_DURATION` |
| Fault injected at | 60 s into the run | `FAULT_AT` |
| Modes in Phase A | `OFF, BASELINE_GT, AQ, WRAPPER_B1, WRAPPER_B2, WRAPPER_B3, CDC, HYBRID` | `MODES=(...)` |
| Repetition ordering | **Interleaved**: rep 1 of every mode, then rep 2, … | avoids confounding a mode with time-of-day drift |
| Mode ordering | **Rotated by repetition index** | cancels a fixed cold-cache advantage for whichever mode runs first |
| Settings guard | `results/matrix-settings.txt` stamps `reps/tps/duration/fault_*` on first use; a resume with different values aborts | prevents an incomparable cell silently entering the matrix |
| One workload iteration | 1 complete A1 lifecycle = `INITIATED → VALIDATED → PROCESSED` (3 transitions), or 2 for the ~4% rejected minority | `harness/k6/a1-workload.js` |
| Workload executor | `constant-arrival-rate`, 100 pre-allocated VUs, 600 max VUs | k6 profile `P1` |

Command that runs one archived cell end to end:

```bash
./scripts/run-experiment.sh --mode WRAPPER_B3 --profile P1 --tps 50 --duration 120s --rep 1
./scripts/run-experiment.sh --mode AQ --profile P1 --rep 1 --fault F8 --fault-at 60
```

Every cell performs the same 12 steps regardless of mode: build the jar once → stop the previous
app instance → reset the workload (reference population kept) → recreate the Kafka topic →
start the app in the requested mode (`ModeActivator` sets triggers/supplemental logging, §6.2) →
register the Debezium connector if the mode needs one, and confirm it is genuinely streaming via
a heartbeat, not merely `RUNNING` → snapshot `V$SYSSTAT` → run k6, injecting the fault at its
scheduled offset → revive the app if a fault killed it, so durable-but-undelivered events are not
miscounted as lost → wait for the pipeline to drain (backlog zero **and** the topic non-empty and
stable — not either alone) → snapshot `V$SYSSTAT` again → export `GROUND_TRUTH` and the topic →
reconcile and append one row to `results/summary.csv`. Full script: `scripts/run-experiment.sh`.

### 6.2 Oracle instance — exact configuration

Queried from the live instance, not the documentation:

| Parameter | Value |
|---|---|
| Version | Oracle AI Database 26ai Free, Release 23.26.3.0.0 |
| `sga_target` / `sga_max_size` | 1,610,612,736 bytes (1.5 GB) |
| `pga_aggregate_target` | 536,870,912 bytes (512 MB) |
| `processes` / `sessions` / `open_cursors` | 200 / 322 / 300 |
| Redo log groups | **2 groups × 10 MB, 1 member each** — the container image default, not overridden |
| `log_mode` | ARCHIVELOG |
| `force_logging` | TRUE |
| `supplemental_log_data_min` | IMPLICIT (database-level minimal supplemental logging, mandatory for LogMiner) |

**The redo log size is stated honestly as a limitation, not tuned away.** Two 10 MB groups
switch every few seconds under a 50 TPS write-heavy mode (AQ in particular, at +171% redo), which
is visible in the alert log as `Thread 1 cannot allocate new log, sequence … Checkpoint not
complete`. This does not invalidate the *relative* comparison between modes — every mode runs
against the same log configuration — but it means the absolute redo-amplification percentages are
specific to a small-redo-log instance and would compress somewhat on a production-sized (multi-GB)
redo configuration, because checkpoint-driven write stalls would be less frequent. Noted as an
open item for anyone re-running this on different hardware.

**Setup is idempotent and split into three scripts** (`scripts/setup-oracle.sh` orchestrates,
skipping the restart-requiring step when already applied):

1. `docker/oracle/init/01_cdb_logging.sql` — `SHUTDOWN IMMEDIATE` → `STARTUP MOUNT` →
   `ALTER DATABASE ARCHIVELOG` → open → `ALTER DATABASE FORCE LOGGING` →
   `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA` (minimal, CDB-wide, mandatory for LogMiner).
2. `docker/oracle/init/02_capture_user.sql` — creates the Debezium capture user
   `c##dbzuser` with a dedicated `LOGMINER_TBS` tablespace **created and quota-granted in all
   three containers individually** (`CDB$ROOT`, `FREEPDB1`, `OBSVPDB`) — `CONTAINER=ALL` on
   `CREATE USER` does not propagate a tablespace quota into each PDB on this release, confirmed
   by inspecting `DBA_TS_QUOTAS` after the all-containers grant. Full grant list:
   `CREATE SESSION, SET CONTAINER`, `SELECT ON V_$DATABASE`, `FLASHBACK ANY TABLE`,
   `SELECT ANY TABLE`, `SELECT_CATALOG_ROLE`, `EXECUTE_CATALOG_ROLE`,
   `SELECT ANY TRANSACTION`, `LOGMINING`, `SELECT` on `V_$LOG`, `V_$LOG_HISTORY`,
   `V_$LOGMNR_LOGS`, `V_$LOGMNR_CONTENTS`, `V_$LOGFILE`, `V_$ARCHIVED_LOG`,
   `V_$ARCHIVE_DEST_STATUS`, `V_$TRANSACTION`, `V_$MYSTAT`, `V_$STATNAME`,
   `EXECUTE ON DBMS_LOGMNR`, `DBMS_LOGMNR_D`, and — the one every generic Debezium-on-Oracle
   guide omits — **`CREATE TABLE`**, because the connector creates a `LOG_MINING_FLUSH` table in
   its own schema on its first streaming iteration to force an LGWR flush, and without it the
   connector snapshots successfully, reports `RUNNING`, then dies with `ORA-01031` the moment it
   starts streaming.
3. `docker/oracle/init/03_pdb_schema.sql` — creates the application schema owner `OBSV` with
   `CREATE SESSION/TABLE/SEQUENCE/PROCEDURE/TRIGGER/VIEW/TYPE/JOB`, plus `SELECT` on the dynamic
   performance views the harness itself reads (`V_$SYSSTAT` for redo bytes and commits,
   `V_$TRANSACTION` for fault F5's long-transaction precondition), and Approach 1's queuing
   privileges: `EXECUTE ON DBMS_AQ/DBMS_AQADM`, `AQ_ADMINISTRATOR_ROLE`, `AQ_USER_ROLE`,
   `EXECUTE ON SYS.AQ$_JMS_TEXT_MESSAGE`.

**Per-mode state is set automatically at application startup**, not by hand — `ModeActivator`
(`src/main/java/.../harness/ModeActivator.java`), an `ApplicationRunner`:

| Mode | `TRG_GROUND_TRUTH` | `TRG_TXN_A1_AQ` | ALL-COLUMN supplemental logging on |
|---|---|---|---|
| `OFF` | disabled | disabled | none |
| `BASELINE_GT` | enabled | disabled | none |
| `AQ` | enabled | enabled | none |
| `WRAPPER_B1/B2/B3` | enabled | disabled | none |
| `CDC` | enabled | disabled | `TXN_A1` |
| `HYBRID` | enabled | disabled | `A1_EVENT_OUTBOX` |

Every candidate table is explicitly turned **off** for modes that do not need it, not merely left
alone — otherwise a CDC run's supplemental logging on `TXN_A1` would still be active for the
wrapper run that followed it, and that run's redo figure would silently include Approach 3's cost.
Current state is read from `USER_LOG_GROUPS` before toggling, because issuing `ADD` when already
present raises `ORA-32588` and `DROP` when absent raises `ORA-32589` — either aborts startup on a
second run of the same mode.

### 6.3 Approach 1 — internal trigger + Oracle AQ

| Component | Detail |
|---|---|
| Queue table | `A1_EVT_QT`, payload type `SYS.AQ$_JMS_TEXT_MESSAGE`, multiple consumers, sorted on `ENQ_TIME` |
| Queue | `A1_EVT_Q`, `max_retries => 5`, `retry_delay => 2` |
| Subscriber | `OBSERVABILITY_BRIDGE` (durable) |
| Capture trigger | `TRG_TXN_A1_AQ` — `COMPOUND TRIGGER` on `TXN_A1`, buffers row changes in `AFTER EACH ROW`, emits once per statement in `AFTER STATEMENT` (limits redo amplification versus emitting per row) |
| Emission filter | Only material state transitions — `INSERTING OR :NEW.STATUS <> :OLD.STATUS` |
| Visibility | `DBMS_AQ.ENQUEUE_OPTIONS_T.visibility := DBMS_AQ.ON_COMMIT` — message becomes visible exactly at commit, rolls back with the transaction |
| Payload construction | `PKG_A1_EVENT.build_payload` — `JSON_OBJECT(...RETURNING CLOB)`, forced into SQL context because `PLS-00684` blocks it as a pure PL/SQL expression; this context switch is a real, measured per-event cost specific to this approach |
| Error handling | **None, deliberately.** No exception handler in `AFTER STATEMENT` — a swallowed error would silently drop an event. This is the code-level source of fault F8's 40% payment failure. |
| Bridge (AQ → Kafka) | `AqToKafkaBridge` — dequeues a **batch of up to 500 messages** (`observability.aq.batch-size`, default 500) with a **500 ms receive timeout** (`observability.aq.receive-timeout`), pipelines the whole batch to Kafka, waits for every acknowledgement, commits the JMS session once per batch — not once per message, which is what makes its throughput comparable to the outbox relay's own batching rather than penalising Approach 1 for an unrelated implementation detail |
| Ordering | Single-threaded bridge, one JMS session; queue table sorted by `ENQ_TIME`; Kafka key = aggregate id, so all events of one transaction share a partition |
| Migrations | `V4__aq_queues.sql` (queue), `V5__plsql_event_package.sql` (package + trigger), `V8__aq_event_id_property.sql` (event-id header parity fix with Approach 2, see the migration's own header comment) |

### 6.4 Approach 2 — application-level transactional outbox

| Component | Detail |
|---|---|
| Table | `A1_EVENT_OUTBOX` — insert-only (no `UPDATE` ever occurs), which is what makes ALL-COLUMN supplemental logging on it nearly free for the hybrid to relay |
| Key columns | `EVENT_ID RAW(16)` (unique), `AGGREGATE_TYPE`, `AGGREGATE_ID`, `EVENT_TYPE`, `EVENT_SEQ`, `PAYLOAD CLOB CHECK (PAYLOAD IS JSON)`, `PUBLISHED_AT` (`NULL` = unclaimed) |
| Claim index | `IX_OUTBOX_PENDING` — function-based, indexes **only unpublished rows**, so the relay's claim query stays O(backlog) rather than O(table) as history grows |
| Write contract | `EMIT_A1_EVENT(p_aggregate_id, p_event_type, p_source, p_payload)` — plain `INSERT`, **no `COMMIT`, no `PRAGMA AUTONOMOUS_TRANSACTION`**; the caller's transaction owns the commit, so a business rollback also rolls back the event |
| Who calls it | The Spring `OutboxWriter` (via `EmitsEvent` AOP) **and** legacy PL/SQL batches, through the identical procedure — this shared contract is the precondition for the hybrid's writer-coverage claim, and fault F11 vs F11B is exactly the test of whether that precondition holds |
| Relay | `OutboxRelay`, `@Scheduled(fixedDelayString = "${observability.outbox.poll-interval:200ms}")` — polls every 200 ms, claims a batch (`observability.outbox.batch-size`, default 500), publishes to Kafka, marks `PUBLISHED_AT` |
| Migration | `V3__outbox.sql` |

### 6.5 Approach 3 — log-based CDC (Debezium)

Full connector configuration submitted to Kafka Connect (`docker/connect/connectors/cdc.json.tmpl`,
`__NAME__`/`__PREFIX__` substituted per run by `scripts/register-connector.sh` — the prefix must
be unique per run or Debezium resumes from a previous run's committed offset and replays events
that have no matching `GROUND_TRUTH` row, scored as phantoms):

```json
{
  "connector.class": "io.debezium.connector.oracle.OracleConnector",
  "tasks.max": "1",
  "database.hostname": "oracle", "database.port": "1521",
  "database.user": "c##dbzuser", "database.dbname": "FREE", "database.pdb.name": "OBSVPDB",
  "table.include.list": "OBSV.TXN_A1",
  "snapshot.mode": "no_data",
  "snapshot.locking.mode": "none",
  "log.mining.strategy": "online_catalog",
  "log.mining.transaction.retention.ms": "180000",
  "heartbeat.interval.ms": "1000",
  "heartbeat.action.query": "UPDATE OBSV.DBZ_HEARTBEAT SET TS = SYSTIMESTAMP WHERE ID = 1",
  "decimal.handling.mode": "string",
  "time.precision.mode": "connect",
  "transforms": "unwrap,route",
  "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
  "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
  "transforms.route.replacement": "bank.a1.transaction.events"
}
```

| Parameter | Value | Why |
|---|---|---|
| `snapshot.mode` | `no_data` | No initial data snapshot — the run starts from the current SCN, capturing only events the workload generates during the run |
| `log.mining.strategy` | `online_catalog` | Avoids the separate LogMiner dictionary-extraction step; adequate because the schema is static within a run |
| `log.mining.transaction.retention.ms` | 180,000 (180 s) | Buffered-transaction retention. **This exact figure is fault F5's target** — a transaction held open longer than this is silently discarded, which the fault test confirms |
| `heartbeat.interval.ms` + heartbeat table | 1,000 ms, `DBZ_HEARTBEAT` | Keeps the connector's offset advancing during idle periods and gives `register-connector.sh` a signal to confirm genuine streaming, not merely `RUNNING` |
| `decimal.handling.mode` | `string` | Avoids floating-point precision loss on `AMOUNT` |
| Supplemental logging required | `TXN_A1` ALL COLUMNS (§6.2) | Without it, `UPDATE` redo carries only changed columns; Debezium fills the rest with type defaults — the "9,003 messages, two-thirds empty" result in §2.2 |

A second template, `cdc-wide.json.tmpl`, is identical except `table.include.list` additionally
carries `OBSV.REDO_NOISE` — used only in experiment C2 to vary the volume of redo the connector
must scan without changing the volume it captures, via the environment variable
`C2_CONNECTOR_TEMPLATE` in `register-connector.sh`.

### 6.6 HYBRID — outbox + Debezium `EventRouter`

Differs from §6.5 in three places (`docker/connect/connectors/hybrid.json.tmpl`):

```json
{
  "table.include.list": "OBSV.A1_EVENT_OUTBOX",
  "predicates.isOutbox.pattern": "__PREFIX__\\.OBSV\\.A1_EVENT_OUTBOX",
  "transforms": "outbox",
  "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
  "transforms.outbox.table.field.event.id": "EVENT_ID",
  "transforms.outbox.table.field.event.key": "AGGREGATE_ID",
  "transforms.outbox.table.field.event.type": "EVENT_TYPE",
  "transforms.outbox.table.field.event.payload": "PAYLOAD",
  "transforms.outbox.route.by.field": "AGGREGATE_TYPE",
  "transforms.outbox.route.topic.replacement": "bank.${routedByValue}.events"
}
```

`transforms.outbox.table.field.event.timestamp` is **deliberately left unset**. Setting it makes
`EventRouter` stamp the Kafka record with the outbox row's `CREATED_AT` — the moment the row was
inserted inside the business transaction — which produced a median end-to-end latency of **−1 ms**
in an earlier draft of this experiment: physically impossible, and it would have reported the
hybrid as the fastest pipeline measured. Left unset, the record carries Kafka's own produce time,
consistent with how every other mode is measured.

### 6.7 Fault injection — exact mechanics (`scripts/inject-fault.sh`)

| Fault | Exact action | What it targets |
|---|---|---|
| F1 / F1R | `kill -9` on the app's PID, restart after 10 s in the same mode | Uncommitted in-flight events at the moment of a hard crash |
| F2 | `docker stop obsv-kafka-2 obsv-kafka-3` for 90 s, then restart | Kafka majority unavailable while one broker survives |
| F3 | `docker stop obsv-connect` for 120 s, then restart | Debezium worker outage and recovery/replay behaviour |
| F4 / F4R | Stop Connect → `ALTER SYSTEM SWITCH LOGFILE` + `ARCHIVE LOG CURRENT` **10 times** (configurable) → `RMAN DELETE NOPROMPT ARCHIVELOG ALL` → restart Connect | Makes the redo window Debezium needs to resume physically unreachable — the permanent-loss condition for pure CDC |
| F5 / F5R | One session, `DBMS_APPLICATION_INFO.SET_MODULE('F5_LONG_TX', NULL)`, inserts 5,000 rows through the outbox contract with `p_commit_every => 0`, then `DBMS_SESSION.SLEEP(240)` before commit | Holds a transaction open 240 s — 60 s past the connector's 180,000 ms retention (§6.5) — to test silent discard |
| F8 | `CREATE OR REPLACE PACKAGE BODY obsv.PKG_A1_EVENT` with `event_type_for` replaced to `RETURN 'broken'` | Makes the capture trigger's package invalid mid-run — the availability-coupling test |
| F11 | `PKG_SYNTH_DATA.generate_transactions(p_count => 20000, p_source => 'BATCH_EOD')` — **no** `p_emit_outbox` | A legacy PL/SQL batch that writes `TXN_A1` directly, bypassing the application and the outbox contract entirely |
| F11B | Same batch, **with** `p_emit_outbox => TRUE` | The same writer, modified to honour the shared `EMIT_A1_EVENT` contract — tests the other side of the hybrid's coverage assumption |

F5's 240-second hold is chosen against two constraints: it must exceed the 180 s retention so the
transaction is actually discarded, and the commit must land inside the measured window (with
`--fault-at 30` and a 420 s run: opened at t=30, retention expires ≈t=210, commits at t=270, run
ends at t=420) or the run would end before the events could have appeared, proving nothing.

### 6.8 Files, for direct inspection

| What | Path |
|---|---|
| Full stack definition | `docker/docker-compose.yml` |
| Oracle bootstrap (3 files) | `docker/oracle/init/01_cdb_logging.sql`, `02_capture_user.sql`, `03_pdb_schema.sql` |
| Idempotent Oracle setup driver | `scripts/setup-oracle.sh` |
| Per-mode trigger/logging activation | `src/main/java/itpu/uz/masterthesisobservability/harness/ModeActivator.java` |
| Mode definitions | `src/main/java/itpu/uz/masterthesisobservability/config/ObservabilityMode.java` |
| Approach 1 schema | `src/main/resources/db/migration/V4__aq_queues.sql`, `V5__plsql_event_package.sql`, `V8__aq_event_id_property.sql` |
| Approach 1 bridge | `src/main/java/itpu/uz/masterthesisobservability/aq/AqToKafkaBridge.java`, `AqJmsConfiguration.java` |
| Approach 2 schema | `src/main/resources/db/migration/V3__outbox.sql` |
| Approach 2 writer/relay | `src/main/java/itpu/uz/masterthesisobservability/outbox/` |
| Approach 3 / HYBRID connector templates | `docker/connect/connectors/cdc.json.tmpl`, `cdc-wide.json.tmpl`, `hybrid.json.tmpl` |
| Connector lifecycle | `scripts/register-connector.sh` |
| One experiment cell | `scripts/run-experiment.sh` |
| The full matrix | `scripts/run-matrix.sh` |
| Fault injection | `scripts/inject-fault.sh` |
| Workload generator | `harness/k6/a1-workload.js` |
| Reconciliation and statistics | `harness/analyze.py`, `harness/aggregate.py` |
