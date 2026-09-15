# The Experiment Harness
## Chapter 6 methodology — how a run is executed, measured and archived

**Status: complete.** All eight modes (`OFF`, `BASELINE_GT`, `AQ`, `WRAPPER_B1/B2/B3`, `CDC`,
`HYBRID`) have run the full matrix — 175 archived cells: 40 steady-state (5 repetitions each),
63 fault, 36 corrected fault reruns, 36 for experiment C2. One command executes one experiment
cell and archives every artefact that produced its numbers.

**This document is the methodology narrative — how the harness was built and what it caught
while being built.** It is not the results chapter. The final, statistically tested numbers
that actually appear in the thesis live in `docs/empirical_comparison_results.md` (the
comparison matrix, §6 for exact configuration) and `docs/fault-matrix-results.md` (the fault
statistics). §7 below predates the full matrix — it is single-run, explicitly-flagged
preliminary data kept because the predictions it made and the bug it caught (§8.6) are part of
the project's real history, not because its numbers are the ones to cite.

---

## 1. Why the harness came before the remaining modes

Risk R2 in the project plan: *manual experiment runs consume all remaining time*. A systems
thesis needs each cell repeated at least five times; without automation that repetition simply
does not happen, and without repetition there is no statistics and therefore no Chapter 6.

Building the harness first also means every mode is measurable the moment it exists, rather than
at the end when there is no time left to fix what the measurements reveal.

---

## 2. One command, one cell

```bash
./scripts/run-experiment.sh --mode WRAPPER_B3 --profile P1 --tps 200 --duration 5m --rep 1
./scripts/run-experiment.sh --mode WRAPPER_B1 --profile P1 --rep 1 --fault F1
```

Eleven steps, all logged:

1. Build the jar once (subsequent runs reuse it).
2. Stop any previous application instance.
3. Reset the workload, **preserving the reference population** so every run starts from an
   identical account base without paying regeneration cost.
4. Delete and recreate the Kafka topic. A fresh topic per run keeps reconciliation unambiguous:
   everything on it belongs to this run, so a stale message cannot be miscounted as a duplicate
   or a phantom.
5. Start the application in the requested mode; `ModeActivator` puts the database triggers into
   exactly the state that mode requires.
6. Snapshot `V$SYSSTAT` and `V$SYSTEM_EVENT`.
7. Run the k6 workload; inject a fault at a scheduled offset if one was requested.
8. **Wait for the pipeline to drain**, polling `obsv_outbox_pending`, rather than sleeping for a
   fixed period. A fixed sleep either wastes time or truncates a slow pipeline — and truncation
   would be scored as event loss, which is exactly the metric under study.
9. Snapshot the database counters again.
10. Export `GROUND_TRUTH` and the Kafka topic.
11. Reconcile, and append one row to `results/summary.csv`.

Everything lands in `results/<run-id>/`: `run.log`, `app.log`, `k6.log`, `k6-summary.json`,
`db_stats_before.csv`, `db_stats_after.csv`, `ground_truth.csv`, `sink.jsonl`, `metrics.json`.
Any number in the thesis can be traced back to the raw data that produced it.

---

## 3. The reconciliation key

`(txn_id, new_status)`.

It is the only key available in **every** mode. Wrapper events carry an event sequence but no
SCN; Debezium change events carry an SCN but no event sequence; AQ messages carry both, in a
different shape. A state transition is uniquely identified by the transaction and the status it
moved to, because an A1 transaction enters each status at most once. The key is therefore
mode-independent, which is what makes the modes comparable at all.

`harness/analyze.py` extracts that key from four different message shapes — the A1Event envelope,
the PL/SQL JSON payload, the Debezium change envelope, and a Debezium envelope with the unwrap
SMT applied — so the same analysis serves every mode without per-mode branching in the metrics.

---

## 4. Metrics produced per run

| Metric | Definition | Source |
|---|---|---|
| `missing` | Committed transitions never delivered | ground truth − sink |
| `phantom` | Delivered transitions never committed | sink − ground truth. **The B1 defect made countable** |
| `loss_rate_ppm` | `missing / ground_truth`, parts per million | derived |
| `loss_rate_upper_bound_95_ppm` | Rule of Three, `3/n`, reported when zero losses are observed | derived |
| `duplicate_rate` | `(total − distinct) / distinct` | sink |
| `ordering_violation_rate` | Fraction of transactions delivered out of state order | sink, by `(partition, offset)` |
| `txns_split_across_partitions` | Must be zero; non-zero means the partition key is wrong | sink |
| `latency_ms_p50/95/99/max` | Kafka record timestamp − commit timestamp | joined |
| `redo_bytes_per_transition` | `Δ redo size / transitions` | `V$SYSSTAT` |
| `user_commits_delta`, `db_block_changes_delta`, `cpu_used_delta`, `log_file_sync_delta_us` | Database cost | `V$SYSSTAT`, `V$SYSTEM_EVENT` |
| `achieved_tps`, `http_p95_ms`, `http_p99_ms` | Client-observed throughput and OLTP latency | k6 |

**On reporting zero loss.** With no observed losses the honest claim is an upper bound, not zero:
"LR = 0" from a finite sample is unfalsifiable. The harness therefore reports
`loss_rate_upper_bound_95_ppm = 3/n` — for the 17 958-transition run below, **LR < 167 ppm at
95 % confidence**. That is a defensible sentence for the results chapter; "no events were lost"
is not.

**On baseline modes.** `OFF` and `BASELINE_GT` emit nothing by design. Scoring them as 100 % loss
would be arithmetically true and analytically meaningless, and would poison any table that
averaged across modes, so the pipeline metrics are blanked and the mode is labelled
`pipeline: none (baseline mode)`.

---

## 5. Workload profiles

| Profile | Shape | Purpose |
|---|---|---|
| P1 | constant arrival rate | Baseline overhead at a sustainable rate |
| P2 | ramp 50 → 1400 TPS | Throughput ceiling per mode |
| P3 | 50 → 800 → 50 | Backlog build-up and recovery time |
| P5 | 1 TPS for hours | Exposes the Debezium offset-stall failure that precedes fault F4 |
| P4 | **not an HTTP workload** | A single large batch generated in-database by `PKG_SYNTH_DATA` — which is precisely what makes it invisible to the wrapper (fault F11) |

One k6 iteration is one complete A1 lifecycle, so rates are in **transactions** per second; a
200 TPS run issues about 600 HTTP requests per second.

---

## 6. Fault injection

`./scripts/inject-fault.sh F1` — standalone, or scheduled by the runner with `--fault F1
--fault-at 60`.

| Case | Fault | Intended discriminator |
|---|---|---|
| F1 | `SIGKILL` the JVM under load | B1 and B2 lose in-flight events; AQ, B3, HYBRID and CDC lose nothing |
| F2 | Kafka majority down 90 s | B1/B2 lose; AQ and B3 accumulate a database-side backlog; CDC buffers in Connect |
| F3 | Connect worker killed 120 s | CDC recovery time and replay duplicate volume |
| F4 | Archive logs purged during a Connect outage | **The key negative result for pure CDC**: permanent, unrecoverable loss |
| F5 | Transaction open beyond `log.mining.transaction.retention.ms` | **CDC discards it silently** |
| F8 | Trigger made invalid | **AQ mode: business transactions fail** — the availability-coupling result |
| F11 | Batch writes bypassing the application | **The wrapper produces zero events**; CDC and the trigger capture all of it |

F4, F5, F8 and F11 are the four that carry the argument of the thesis. A fault that hurts every
mode equally would tell it nothing.

---

## 7. Validation runs

> **Superseded by the full matrix — kept for the narrative, not for citation.** Every table in
> this section is n = 1: a single run per mode, run early to prove the harness itself worked
> before committing to five repetitions of everything. Where a number here disagrees with
> `docs/empirical_comparison_results.md` — e.g. AQ redo reads +136.6% here and +171.4% in the
> final matrix — the final matrix number is correct; the difference is exactly the run-to-run
> variance these single runs warn about in their own text (§7.1, §7.2). Two things below **are**
> still live: the hybrid-latency retraction (§7.2, confirmed in the final matrix at 3,186 ms)
> and the predicted-vs-measured table, which is what the thesis's refuted-predictions claim
> (§2.1 of the results chapter) draws on.

Two cells executed, 60 s at 100 TPS each. **Single runs — not statistically significant, and
reported here only to demonstrate that the instrument works.**

| Mode | Transitions | missing | phantom | duplicates | OVR | LR upper bound | latency p50 / p95 / p99 |
|---|---|---|---|---|---|---|---|
| `BASELINE_GT` | 18 003 | — | — | — | — | n/a | n/a |
| `WRAPPER_B3` | 17 958 | **0** | **0** | **0** | **0.0** | **< 167 ppm** | 136 / 284 / 1536 ms |

Database cost, from `V$SYSSTAT` deltas:

| Mode | redo bytes / transition | commits | achieved TPS | HTTP p95 |
|---|---|---|---|---|
| `BASELINE_GT` | 4 024 | 18 016 | 91.1 | 5.04 ms |
| `WRAPPER_B3` | 8 110 | 18 213 | 90.9 | 8.39 ms |
| **Outbox mechanism** | **+4 086 (+101.5 %)** | +197 | −0.2 | +3.35 ms |

The outbox roughly **doubles** redo per transition. That matches the qualitative prediction made
in the analysis document — the payload is written twice, once as the business row and once as the
event — and the agreement between prediction and measurement is itself worth reporting.

### 7.1 First comparison including Approach 1

Four cells, 60 s at a 50 TPS target, all four run back to back on an otherwise idle machine so
that they are directly comparable. **Single runs. Not statistically significant.** They are
reported to show that Approach 1 is now instrumented on the same terms as Approach 2, and
because two of the differences are large enough to be worth stating as hypotheses for the
replicated matrix.

| Mode | Transitions | missing | phantom | duplicates | OVR | LR upper bound | latency p50 / p95 / p99 |
|---|---|---|---|---|---|---|---|
| `OFF` | — | — | — | — | — | n/a | n/a |
| `BASELINE_GT` | 9 000 | — | — | — | — | n/a | n/a |
| `AQ` | 9 003 | **0** | **0** | **0** | **0.0** | **< 333 ppm** | **7 / 16 / 1 149 ms** |
| `WRAPPER_B3` | 9 000 | **0** | **0** | **0** | **0.0** | **< 333 ppm** | 125 / 229 / 1 368 ms |

| Mode | redo bytes / transition | user commits | achieved TPS | HTTP p95 | HTTP p99 |
|---|---|---|---|---|---|
| `OFF` | n/a | 9 003 | 45.6 | 7.29 ms | 42.3 ms |
| `BASELINE_GT` | 4 236 | 9 008 | 47.7 | 6.60 ms | 18.2 ms |
| `AQ` | 10 022 (**+136.6 %**) | 12 366 (**+3 358**) | 45.6 | 8.46 ms | 37.6 ms |
| `WRAPPER_B3` | 8 158 (**+92.6 %**) | 9 265 (+257) | 45.5 | 9.84 ms | 166 ms |

Three observations, in decreasing order of confidence.

**Median latency differs by roughly 18×, and the cause is structural rather than incidental.**
The outbox relay polls on a 200 ms fixed delay, so a row waits on average half an interval
before it is even seen; 100 ms of expected polling delay plus publication accounts for the
measured 125 ms almost exactly. Advanced Queuing has no polling interval at all — the bridge is
blocked in `DBMS_AQ.DEQUEUE` and is woken by the enqueue — and measures 7 ms. This is not a
tuning artefact and it will not disappear with replication: it is the difference between being
notified and asking repeatedly. It is also the single strongest argument for the hybrid
recommendation, which removes the poll without adding a queue.

**Advanced Queuing costs more redo than the outbox, not less** — +136.6 % against the control
versus +92.6 %. The direction is worth stating because it contradicts the intuition that keeping
the event inside the database avoids writing it twice. The event is written twice either way;
AQ additionally generates redo for the dequeue, which mutates message state in the queue table,
and for its own transactional bookkeeping. The extra 3 358 commits are the bridge's own session
commits, one per dequeued batch.

**Approach 1 was cheaper on the OLTP critical path than the outbox in this run** (HTTP p99
37.6 ms versus 166 ms), which is the opposite of what the analysis document predicts. One run
is not evidence for a claim this counter-intuitive; the plausible mechanism is contention
between the relay's `FOR UPDATE SKIP LOCKED` claim and concurrent inserts on the same outbox
table, and it needs replication and a wider TPS sweep before it is asserted. Recorded here as a
hypothesis, not a result.

Note also that the `OFF` and `BASELINE_GT` HTTP percentiles are inverted relative to
expectation — the uninstrumented baseline measured *slower* than the instrumented one. At n = 1
that is noise, and it is a useful calibration of how much run-to-run variation this rig has:
enough to invert a small difference, which is why the matrix specifies at least five
repetitions per cell.

### 7.2 All six pipelines measured

Six cells, 60 s at a 50 TPS target, run back to back. **Single runs. Not statistically
significant.** Reported because every approach in the thesis is now instrumented on identical
terms, and because the latency ordering is large enough to survive any plausible variance.

| Mode | Transitions | missing | phantom | dup | OVR | latency p50 / p95 / p99 |
|---|---|---|---|---|---|---|
| `OFF` | — | — | — | — | — | n/a |
| `BASELINE_GT` | 9 000 | — | — | — | — | n/a |
| `AQ` | 9 003 | 0 | 0 | 0 | 0.0 | **7 / 16 / 1 149 ms** |
| `WRAPPER_B3` | 9 000 | 0 | 0 | 0 | 0.0 | 125 / 229 / 1 368 ms |
| `CDC` | 9 003 | 0 | 0 | 0 | 0.0 | 2 613 / 5 734 / 6 945 ms |
| `HYBRID` | 9 000 | 0 | 0 | 0 | 0.0 | 3 360 / 6 603 / 7 510 ms |

All four pipelines delivered every committed transition, in order, exactly once. Each therefore
carries the same Rule-of-Three bound, **LR < 333 ppm at 95 % confidence**: at this sample size
the reliability of the four mechanisms is not distinguishable, and any thesis claim that one is
"more reliable" than another must come from the fault matrix, not from the clean runs.

| Mode | redo bytes / transition | vs control | user commits | HTTP p95 | HTTP p99 |
|---|---|---|---|---|---|
| `BASELINE_GT` | 4 236 | — | 9 008 | 6.60 ms | 18.2 ms |
| `AQ` | 10 022 | **+136.6 %** | 12 366 | 8.46 ms | 37.6 ms |
| `WRAPPER_B3` | 8 158 | **+92.6 %** | 9 265 | 9.84 ms | 166 ms |
| `CDC` | 3 898 | **−8.0 %** | 9 072 | 6.78 ms | 33.6 ms |
| `HYBRID` | 8 918 | **+110.5 %** | 9 098 | 9.44 ms | 193 ms |

**Predicted against measured.** The latency table in the analysis document gave indicative
bands before any of this was built. Three of the four hold:

| Pipeline | Predicted p50 | Measured p50 | |
|---|---|---|---|
| Trigger + AQ | 10–50 ms | 7 ms | slightly better than predicted |
| Outbox + polling relay | 100–300 ms | 125 ms | within band |
| CDC via LogMiner | 1–5 s | 2 613 ms | within band |
| Outbox + Debezium relay | 0.5–2 s | 3 360 ms | **above band, and slower than plain CDC** |

The hybrid is the one that missed, and it missed in the direction that matters: it was predicted
to be the faster of the two Debezium pipelines and measured as the slower. The plausible
mechanism is `lob.enabled=true` — the outbox payload is a CLOB, so mining it costs per-event work
that mining `TXN_A1`'s scalar columns does not. That is a testable hypothesis, not yet a result.

A claim in the code has been retracted on the strength of this: `OutboxRelay` previously stated
that the Debezium relay "removes the polling query entirely and cuts end-to-end latency". The
first half is true and the second is false by a factor of 27. What the hybrid actually buys is
coverage of writers that never call the application, and the removal of polling load from the
OLTP instance — not latency.

**`CDC` costs the database essentially nothing on the transaction path.** Its redo per transition
and its HTTP percentiles are indistinguishable from the uninstrumented control, which is the
expected result rather than a surprising one: Approach 3 adds nothing to the business
transaction, and its only in-transaction cost is ALL-column supplemental logging. The measured
−8 % is noise, not a saving — and it usefully calibrates this rig, whose run-to-run redo
precision at n = 1 is therefore no better than roughly ±10 %. That is by itself the argument for
the matrix's five repetitions per cell.

**Supplemental logging is switched per mode, not left on.** ALL-column supplemental logging makes
Oracle write the whole row to redo on every UPDATE whether or not anyone is mining it. Enabling
it once on `TXN_A1` and leaving it there would have added Approach 3's redo cost to the
measurement of every other approach, including the baselines, and would have understated how
much CDC costs relative to the alternatives. `ModeActivator` therefore enables it on exactly the
table the active mode captures and disables it everywhere else, in the same way and for the same
reason that it manages the capture triggers.

---

## 8. Six defects the harness found in its own subject

All six were found by *measuring*, not by reading the code, and each is the kind of finding that
justifies building a real system rather than describing one.

### 8.1 The sequential relay: latency was 58× worse than the pattern requires

First implementation published one record at a time and blocked on each acknowledgement,
capping the relay at roughly one record per broker round trip. At 150 events/s this built a
multi-second backlog:

| | p50 | p95 | p99 |
|---|---|---|---|
| Sequential publish | 7 416 ms | 11 808 ms | 13 731 ms |
| Batched publish | **136 ms** | **284 ms** | **1 536 ms** |

The measured latency had been a property of the relay implementation, not of the outbox pattern.
Had this gone unnoticed, the thesis would have reported the outbox as a multi-second-latency
mechanism and drawn the wrong conclusion in the comparison matrix.

### 8.2 `ROWNUM` is applied before `ORDER BY` — silent event reordering

The claim query used `WHERE ROWNUM <= n ... ORDER BY ID`, which in Oracle takes an **arbitrary**
n rows and then sorts those. Measured effect: **2.6 % of transactions delivered out of order** —
for example `PROCESSED` at offset 13 ahead of `VALIDATED` at offset 67, while the outbox rows
themselves were correctly ordered (IDs 9027 → 9160 → 9294).

This defect loses nothing, so no loss metric detects it. Only the ordering metric does — which
is the argument for measuring ordering at all.

Both obvious remedies fail on Oracle:

```sql
SELECT ... FROM (SELECT ... ORDER BY ID) WHERE ROWNUM <= n FOR UPDATE SKIP LOCKED;
-- ORA-02014: cannot select FOR UPDATE from view with DISTINCT, GROUP BY, etc.

SELECT ... ORDER BY ID FETCH FIRST n ROWS ONLY FOR UPDATE SKIP LOCKED;
-- ORA-02014 as well: FETCH FIRST is rewritten as an analytic-function view.
```

What works is two statements — establish the high-water ID of the ordered first *n* rows, then
lock that range, the second statement having no inline view:

```sql
SELECT MAX(ID) FROM (
  SELECT ID FROM A1_EVENT_OUTBOX WHERE PUBLISHED_AT IS NULL ORDER BY ID)
 WHERE ROWNUM <= :batchSize;

SELECT ... FROM A1_EVENT_OUTBOX
 WHERE PUBLISHED_AT IS NULL AND ID <= :highWater
 ORDER BY ID FOR UPDATE SKIP LOCKED;
```

After the fix, `ordering_violation_rate` is **0.0**.

---

### 8.3 The settle condition was blind outside outbox modes

The harness waits for the pipeline to drain before it exports and reconciles, because
truncating a slow pipeline scores as event loss. That wait watched `obsv_outbox_pending`, a
meter that only exists when an outbox relay is running. In `AQ` and `CDC` runs the metric is
absent, the scrape returned nothing, the shell defaulted it to zero, and the loop exited on its
first iteration having verified nothing — the run then relied entirely on the fixed 10-second
sleep that follows.

At the validated load the AQ bridge drains in single-digit milliseconds, so this changed no
result. At a load where the bridge fell behind it would have exported a partial topic and
reported the remainder as **lost events**, attributing a fabricated reliability defect to
Approach 1. The condition is now read from the database by `pending-count.sql`, which sums
unpublished outbox rows and `READY`/`WAIT` AQ messages, so it means the same thing in every
mode; a run that fails to drain within the limit is now flagged in its log rather than analysed
silently.

### 8.4 A swallowed queue purge would have manufactured phantom events

`reset-workload.sql` purged the AQ queue table inside `EXCEPTION WHEN OTHERS THEN NULL`. A
failed purge leaves messages from a previous run in the queue; the bridge dequeues and
republishes them, and reconciliation counts them as **phantom** events — deliveries with no
corresponding committed transaction, which is the signature of the dual-write anti-pattern this
thesis exists to measure. The purge now verifies its own result and raises `ORA-20010` if the
queue is not empty, and the runner aborts the cell instead of continuing.

### 8.5 CDC without per-table supplemental logging: the right number of empty events

The most instructive defect in the whole harness so far.

With the Debezium connector correctly registered, streaming, and reporting no error, the first
CDC run published **9 003 messages for 9 003 committed state transitions**. Every count matched.
Every message was valid JSON with the expected field names. The connector's status was RUNNING
throughout and its log contained no warning.

Reconciliation on `(txn_id, new_status)` reported a 66.7 % loss rate. Two-thirds of the messages
looked like this:

```json
{ "TXN_ID": "0", "TXN_REF": "", "DEBIT_ACCOUNT": "", "AMOUNT": "0.0000",
  "STATUS": "VALIDATED", "UPDATED_AT": 1788438647673, "VERSION": "1" }
```

The `INSERT` events were complete; every `UPDATE` event had its unchanged columns replaced by
type defaults. The cause is that `TXN_A1` carried only the database's minimal supplemental
logging, so the redo record for an UPDATE contains the changed columns and the row identifier
and nothing else. Debezium does not fail on this — it fills what the redo does not supply.

The consequence is the point. **Every count-based validation passes perfectly**: the number of
events equals the number of transitions, no message is malformed, no message is missing, the
connector reports healthy, and the lag metrics are flat. A monitoring dashboard built on event
counts — which is what most production CDC deployments actually have — would show a fully
healthy pipeline delivering two-thirds unusable events. Only reconciliation against an
independent ground truth on a *semantic* key exposes it.

This is the single strongest justification for the methodology of this thesis. Counting events
is not measuring a pipeline.

The fix is `ALTER TABLE ... ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS` on each captured table.
After it, the same run reported 9 003 / 9 003 matched with zero loss, zero phantoms and zero
ordering violations.

### 8.6 The hybrid measured a median latency of −1 ms

The outbox `EventRouter` accepts `table.field.event.timestamp`, which stamps the Kafka record
with a column from the outbox row. Configured with `CREATED_AT`, the record carries the moment
the row was inserted **inside** the business transaction. End-to-end latency, computed as
arrival minus commit, then measures the gap between an insert and the commit that follows it:
a median of **−1 ms**, a mean of 1.2 ms, and a p99 of 7 ms.

Had the sign been positive it would have read as a spectacular result — the hybrid delivering
events to Kafka in about a millisecond, an order of magnitude faster than Advanced Queuing and
three orders faster than plain CDC — and it would have gone into the recommendation chapter.
What made it detectable was that latency cannot be negative between two processes on one host.

Two changes followed. The connector no longer overrides the record timestamp, so every mode is
measured on produce time. And `analyze.py` now counts negative latencies, reports
`latency_negative_samples` in every result, and prints a warning when they exceed 1 % of the
sample, because this failure mode disguises itself as good news rather than bad.

With the override removed the hybrid measures 3 360 ms at p50 — 3 400 times slower than the
figure the misconfiguration produced.

All six defects share the shape of environment finding 20: **nothing failed loudly, and the
damage would have been indistinguishable from a genuine property of the mechanism under test.**
Three of the six (§8.2, §8.5, §8.6) would have produced a *better-looking* result than the truth.

## 9. Files

| Path | Purpose |
|---|---|
| `scripts/run-experiment.sh` | The orchestrator: one command, one archived cell |
| `scripts/inject-fault.sh` | Fault cases F1–F5, F8, F11 |
| `harness/k6/a1-workload.js` | Workload profiles P1, P2, P3, P5 |
| `harness/analyze.py` | Reconciliation: loss, phantom, duplicate, ordering, latency |
| `harness/summarise.py` | Appends one row to `results/summary.csv` |
| `harness/sql/dump-ground-truth.sql` | Control-instrument export |
| `harness/sql/snapshot-stats.sql` | `V$SYSSTAT` / `V$SYSTEM_EVENT` counters |
| `harness/sql/reset-workload.sql` | Clears workload and the AQ backlog, preserves reference data |
| `harness/sql/pending-count.sql` | Per-mode in-database backlog, used by the settle wait |
| `scripts/register-connector.sh` | Registers the Debezium connector and gates on proof of streaming |
| `docker/connect/connectors/cdc.json.tmpl` | Approach 3: mines `TXN_A1` directly |
| `docker/connect/connectors/hybrid.json.tmpl` | Recommended: mines `A1_EVENT_OUTBOX` via `EventRouter` |
| `scripts/run-matrix.sh` | Runs the full matrix: interleaved repetitions, rotated mode order, resumable |
| `results/summary.csv` | One row per run, ready for the analysis notebook |
| `results/aggregate-P1.md` | Final statistics — exact permutation tests, the numbers actually cited in Chapter 6 |
| `docs/empirical_comparison_results.md` | The results chapter itself; §6 has exact configuration for every mechanism |

---

## 10. Status — what was planned here, and what actually happened

This section originally tracked what remained before the full matrix could run. All of it is
now done; kept as a record rather than deleted, because two items resolved differently than
planned and that is itself worth knowing before reading Chapter 6.

1. ~~**AQ mode**~~ — done. Compound trigger to `PKG_A1_EVENT` to `DBMS_AQ`, drained by
   `AqToKafkaBridge` over AQ-JMS.
2. ~~**CDC and HYBRID modes**~~ — done. Registration is gated on a heartbeat message proving
   the connector is streaming, and each run uses a unique `topic.prefix` so that a new cell can
   never resume from the previous cell's SCN and replay its events as phantoms.
3. ~~**The full matrix**~~ — done. 8 modes × 5 repetitions steady-state, plus the fault cases,
   plus experiment C2 — 175 archived cells in total. Interleaved and rotated by
   `scripts/run-matrix.sh` (§2 of `docs/empirical_comparison_results.md` states the exact
   design). Final numbers: `docs/empirical_comparison_results.md` §1.
4. **The `log.mining.sleep.time.*` question (claim C2)** — resolved, but not the way this
   section originally framed it. Rather than a latency/load sweep, C2 varied the *volume of
   redo the connector must scan* while holding the captured workload constant, and measured
   database CPU as a difference against the connector-absent run. Result: mining cost rises at
   13.0 CPU-seconds per GB of *discarded* redo (95% bootstrap CI 5.86–18.62), and at the
   highest tested level 79% of CDC's database-side cost was spent scanning redo that never
   became an event. A companion test, C2b, is reported **inconclusive** — its control run
   failed, and that failure is stated rather than patched over. Full detail:
   `docs/empirical_comparison_results.md` §2.5.
5. **The dump-schema defect** — fixed. The ground-truth export must run with
   `ALTER SESSION SET CURRENT_SCHEMA = OBSV`; connected as SYS the unqualified table name
   resolved to nothing and the spool produced an error page rather than data, which the
   analysis then scored as 100% phantom events. A reminder that a silent export failure looks
   exactly like a catastrophic pipeline failure — the same shape as every defect in §8.

**What was not anticipated when this list was written:** three predictions this thesis made
before the matrix ran were tested and refuted rather than confirmed — purging archive logs
after forced switches, holding a transaction past its retention, and the hybrid's expected
speed advantage (§7.2, §8.6). None of that was visible from this remaining-work list; it only
became visible by running the matrix the list was tracking progress toward.
