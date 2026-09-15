# Fault Matrix Results — the evidence for claim C1

## Chapter 6 · 63 fault cells plus 36 corrected reruns, three repetitions each

Clean running could not separate the six pipelines: every one delivered ~90 000 transitions with
zero loss, zero duplicates and zero reordering. That was expected, and it is why claim C1 rests
on this chapter rather than on the steady-state runs.

**Two of the six faults produced the discrimination the thesis needs. Four produced negative
results. Two of the six did not measure what they were designed to measure on the first pass;
they were corrected and rerun, and §7 reports both passes.**

> **Read §7 first for the conclusions.** §§1–6 are the original pass, retained because two of its
> readings were wrong and the corrections are themselves part of the evidence.

---

## 1. F11 — writes that bypass the application

The decisive result, and the cleanest.

`PKG_SYNTH_DATA.generate_transactions` writes A1 transactions directly in PL/SQL, as an
end-of-day batch would. Three repetitions, ~87 000 transitions each.

| Mode | Missing | Loss rate |
|---|---|---|
| `AQ` | 0 / 86 990 | **0 %** |
| `CDC` | 0 / 86 994 | **0 %** |
| `WRAPPER_B3` | 59 983 / 86 984 | **69 %** |
| `HYBRID` | 59 990 / 86 991 | **69 %** |

Reproducibility is near-exact: 59 979 / 59 997 / 59 973 for `WRAPPER_B3` across three runs.

**This turns assumption A-3 from an argument into a number.** The wrapper cannot observe a writer
that does not call it. The trigger and the redo log observe everything that reaches the database,
whatever wrote it.

### The finding that changes the recommendation

**`HYBRID` failed identically to the plain wrapper.** This was not the prediction. The analysis
document argues that the hybrid achieves complete writer coverage because the Spring
`OutboxWriter` and legacy PL/SQL batches both write through the same `EMIT_A1_EVENT` contract.

They do — *if the legacy writer is modified to call it*. `PKG_SYNTH_DATA` was written to model an
**unmodified** legacy writer, and it does not call `EMIT_A1_EVENT`. So the measurement shows what
happens when the hybrid's central assumption is not honoured: **the hybrid inherits the wrapper's
blind spot exactly.**

This is worth more than a caveat. The hybrid's writer coverage is not a property of the
architecture; it is a property of an organisation's willingness to modify every writer. Chapter 7
must state it in those terms, and the recommendation must be conditional on it.

**Planned extension.** Rerun F11 with a batch that *does* call `EMIT_A1_EVENT`, so the assumption
is measured on both sides: coverage when honoured, and coverage when not. That converts the
weakest point of the recommendation into its best-evidenced one.

---

## 2. F8 — a capture defect that stops payments

The availability-coupling result, and decisive.

The fault replaces `PKG_A1_EVENT`'s body with one that no longer offers `emit_state_change`,
invalidating the capture trigger. In `AQ` mode the trigger runs inside the business transaction,
so the DML fails with it.

| Repetition | HTTP requests | Failure rate | Achieved TPS | Transitions |
|---|---|---|---|---|
| r1 | 14 991 | **40.06 %** | 15.4 | 8 985 |
| r2 | 14 998 | **40.03 %** | 15.4 | 8 995 |
| r3 | 15 000 | **40.00 %** | 15.4 | 9 000 |
| *clean `AQ`* | 18 003 | 0.00 % | 45.6 | ~27 000 |

Throughput fell by 66 % and two fifths of all customer requests failed. **A defect in the
observability mechanism stopped payments.**

Note where the result lives: not in the loss column, which reads zero. Nothing was lost because
nothing committed. The result is visible only in throughput and error rate — which is itself
worth stating, because a reliability study that looked only at event loss would have recorded
this fault as harmless.

---

## 3. F1 — process kill under load, and a measurement that had to be corrected

Raw output, three repetitions:

| Mode | Missing (r1 / r2 / r3) |
|---|---|
| `CDC` | 0 / 0 / 0 |
| `HYBRID` | 0 / 0 / 0 |
| `WRAPPER_B1` | 0 / 2 / 1 |
| `WRAPPER_B2` | 1 / 2 / 0 |
| `AQ` | 2 / 2 / 1 |
| `WRAPPER_B3` | **15 / 12 / 14** |

Read naively this says the transactional outbox is an order of magnitude worse than the dual
write it exists to replace. That reading is wrong, and **the harness detected it at the time**.
Every one of those three runs logged:

```
OGOHLANTIRISH: pipeline 120s ichida bo'shamadi (db_pending=15 sink=8964)
               - LOSS raqamlari ishonchsiz
```

`db_pending` was 15, 12 and 14 — matching the "missing" counts exactly. Those events are outbox
rows that were **committed and durable**, waiting for a relay that had been killed along with the
JVM. They are not lost; they are undelivered, and on restart they would be published. The same
applies to AQ's 2 / 2 / 1, which are messages sitting in the queue awaiting the dead bridge.

`WRAPPER_B1`'s and `WRAPPER_B2`'s handful, by contrast, are genuinely unrecoverable: published
into a window the crash destroyed.

**The defect is in the measurement, not the mechanism.** "Missing at the moment the run ended"
conflates *lost* with *not yet delivered because the deliverer is dead* — and the distinction is
the entire point of the outbox pattern.

**Correction to apply.** After a process-kill fault the application must be restarted and the
pipeline allowed to drain before the topic is exported. Only then does "missing" mean
unrecoverable. Until that rerun, F1's numbers are reported here with the correction stated and
are not used to rank the mechanisms.

---

## 4. F2 — brokers unavailable: a clean negative result

Kafka majority down for 90 s. **Every mode lost nothing**, across 81 000 transitions each.

Producers buffered through the outage, the queue and the outbox accumulated on the database side,
and the connector resumed from its committed offset. The settle wait then let all of them drain
before the export.

This is a real result and belongs in the thesis as one: **transient broker unavailability is not
a discriminating fault.** It is the failure practitioners worry about most, and on this evidence
it is the one that matters least — every mechanism examined tolerates it, because every one of
them has somewhere to buffer.

---

## 5. F4 and F5 — did not reproduce their intended conditions

Reported because a fault matrix that only lists its successes is not evidence.

### F4 — archive logs purged during a connector outage

Designed as the key negative result for pure CDC: a mined window destroyed, its events
unrecoverable, no artefact recording that they existed.

Measured: `CDC` 0 missing, `HYBRID` 0 missing, three repetitions each.

The condition did not arise. With `snapshot.mode=no_data` and `log.mining.strategy=online_catalog`,
and an outage short relative to the redo log switch interval, the connector resumed from an SCN
still present in the online logs and never needed the purged archives. Reproducing the intended
condition requires the outage to outlast several log switches, which needs either a longer outage
or a much smaller redo log.

### F5 — a transaction held open past the connector's retention

Designed to show CDC discarding a buffered transaction silently.

Measured: `CDC` 0 missing; `HYBRID` 29 985 missing of 155 808.

The `HYBRID` figure is not a retention effect. F5 creates its long transaction through
`PKG_SYNTH_DATA` — the same batch writer as F11 — so for any outbox-based mode the events are
missing because nothing wrote them to the outbox, exactly as in §1. 5 000 transactions × 3
transitions × 2 runs = 30 000, which is the number observed.

**F5 as implemented is confounded with F11 for every outbox mode, and did not trigger the
retention path for CDC.** To isolate it the long transaction must be opened by a writer whose
events *do* reach the outbox, and must be held past `log.mining.transaction.retention.ms` while
the connector is actively mining.

---

## 6. What the fault matrix establishes, stated conservatively

| Claim | Status |
|---|---|
| A mechanism inside the transaction sees writers the application does not | **Established.** F11: AQ and CDC 0 %, outbox-based modes 69 % |
| The hybrid's writer coverage depends on modifying every writer, and fails identically to the wrapper when they are not modified | **Established**, and it was not predicted |
| Coupling capture to the transaction couples availability to it | **Established.** F8: 40 % of requests failed, throughput −66 % |
| Transient broker loss discriminates between these mechanisms | **Refuted.** F2: no mode lost anything |
| The naive wrapper variants lose events on process death where the atomic ones do not | **Supported but not yet clean.** F1 needs the post-restart drain before the numbers can carry it |
| CDC loses events permanently when archives are purged | **Not established.** F4 did not reproduce its condition |
| CDC discards long transactions silently | **Not established.** F5 was confounded |

Four of seven statements are supported by the data as it stands. Two require reruns that are
already specified. One is refuted, which is a result.

---

## 7. The corrected reruns — results

All four reruns completed, 3 repetitions each, under new labels so that runs taken before and
after each measurement fix stay separable.

### F1R — process kill, with the application revived and the pipeline drained before export

The correction is decisive, and it reverses the raw reading of §3 completely.

| Mode | Missing (r1 / r2 / r3) | Before the fix |
|---|---|---|
| `AQ` | **0 / 0 / 0** | 2 / 2 / 1 |
| `WRAPPER_B3` | **0 / 0 / 0** | 15 / 12 / 14 |
| `CDC` | **0 / 0 / 0** | 0 / 0 / 0 |
| `HYBRID` | **0 / 0 / 0** | 0 / 0 / 0 |
| `WRAPPER_B1` | **1 / 1 / 0** | 0 / 2 / 1 |
| `WRAPPER_B2` | **1 / 1 / 1** | 1 / 2 / 0 |

**This is claim C1.** The four patterns that write the event atomically with the business change
lose nothing when the process is killed under load. The two naive wrapper variants lose events:
`WRAPPER_B2` in every repetition, `WRAPPER_B1` in two of three. Nothing else did, in any
repetition.

The magnitudes are small — one or two events per run out of roughly 9 000 — and they should be.
A single `SIGKILL` catches only what happens to be in flight at that instant, so the window is
narrow by construction. What matters is that it is **never zero for the two patterns that have a
window, and always zero for the four that do not.**

Stated conservatively: at ~27 000 transitions per mode, `WRAPPER_B2`'s three losses give a point
estimate of ~114 ppm while the atomic patterns carry a Rule-of-Three bound below 111 ppm. Those
figures do not separate cleanly on their own, and the thesis will not claim they do. **The
separation here is mechanistic and the observation is consistent with it**: the two patterns with
a loss window by construction lost events every time or nearly every time, and the four without
one never did. Sharpening it statistically needs many more crash events, not more transitions per
crash — a limitation worth stating rather than papering over.

### F11B — the batch writing through the shared outbox contract

| Mode | Missing / committed | Loss |
|---|---|---|
| `WRAPPER_B3` | 0 / 86 577 · 0 / 86 982 · 0 / 86 991 | **0 %** in all three |
| `HYBRID` | 62 231 / 86 517 · 0 / 86 793 · 0 / 86 979 | 71.9 %, then **0 %**, **0 %** |

**The assumption is now measured on both sides.** With an unmodified legacy writer (F11, §1) the
outbox and the hybrid both lose 69 %. With a writer that calls `EMIT_A1_EVENT`, both recover
complete coverage. The hybrid's writer coverage is therefore real and achievable — and entirely
conditional on every writer being modified to use the contract.

`HYBRID r1`'s 71.9 % is **not** a property of the mechanism; it is the harness's drain check
firing early, and it has been fixed. The run log shows the drain declaring the pipeline empty at
`sink=24286` while Debezium was still working through an 86 517-transition backlog: the sink had
been momentarily static for three polls, and Debezium's mining cycle has gaps longer than that.
The check now compares the sink against the committed transition count directly — completeness
rather than stillness — with a static sink retained only as a fallback so a genuinely lossy run
still terminates. **The two sibling repetitions reaching exactly 0 % is what identifies r1 as an
instrument artefact rather than a result.**

### F4R — archives purged with ten forced log switches

| Mode | Missing / committed |
|---|---|
| `CDC` | 0 / 45 003 · 0 / 45 003 · 0 / 45 003 |
| `HYBRID` | 0 / 44 595 · 0 / 44 250 · 0 / 45 003 |

**A negative result, and now a robust one.** The first attempt switched the log twice and was
dismissed as not having reproduced the condition. The strengthened version cycles the log ten
times, archiving each switch before deleting every archive, and the connectors still lost
nothing. With `snapshot.mode=no_data` and `log.mining.strategy=online_catalog`, a connector
restarting after a short outage resumes from an SCN still present in the online logs and never
reads an archive at all.

The analysis document offers this as "the key negative result for pure CDC — permanent,
unrecoverable loss". **On this evidence, at this outage length, it does not occur.** Reproducing
it would need the outage to outlast the online log's ability to hold the required SCN, which on
this instance means either a much longer outage or much smaller redo logs. The claim should be
narrowed to those conditions rather than stated generally.

### F5R — a transaction held open past the connector's retention

| Mode | Missing / committed |
|---|---|
| `CDC` | 0 / 78 000 · 0 / 77 997 · 0 / 77 997 |
| `HYBRID` | 0 / 77 268 · 0 / 77 976 · 0 / 78 003 |

The confound identified in §5 is gone: the long transaction now writes outbox rows, so the
retention path was genuinely exercised for both modes. The transaction was held open for 240 s
against a configured `log.mining.transaction.retention.ms` of 180 000 ms.

**Nothing was discarded.** Debezium 3.5 delivered every event of a transaction held open a third
longer than its configured retention. This contradicts the prediction that CDC "discards the
buffered transaction silently", and it is reported as a refutation of that prediction under these
conditions. Whether a longer hold, a larger transaction, or a different Debezium version behaves
differently is untested here.

---

## 8. What the fault matrix establishes, after the corrections

| Claim | Status |
|---|---|
| A mechanism inside the transaction sees writers the application does not | **Established.** F11: AQ and CDC 0 %, outbox-based modes 69 % |
| The hybrid's coverage is conditional on modifying every writer, and complete once they are | **Established on both sides.** F11 69 % unmodified, F11B 0 % modified |
| Coupling capture to the transaction couples availability to it | **Established.** F8: 40.0 % of requests failed, throughput −66 % |
| Naive wrapper variants lose events on process death; atomic patterns do not | **Supported, mechanistically clean, statistically weak.** F1R: B1 and B2 lost in 5 of 6 runs, the four atomic patterns in 0 of 12 |
| Transient broker loss discriminates between the mechanisms | **Refuted.** F2: no mode lost anything |
| CDC loses events permanently when archives are purged | **Refuted at this outage length.** F4R: zero loss with ten log switches |
| CDC discards long transactions silently | **Refuted at this hold length.** F5R: zero loss at 240 s against a 180 s retention |

Three of seven are established, one is supported with a stated statistical limitation, and
**three are refuted**. The refutations are results, and two of them contradict predictions made
in this thesis's own analysis document before any of it was built.
