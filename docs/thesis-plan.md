# Master's Thesis Execution Plan
## "Event-Based Observability of Transaction Processing in Bank Operations"

**Repository:** `master-thesis-observability` · ITPU
**Baseline schedule:** 20 weeks — **actually being executed on a 1-month deadline** (started 2 Sep 2026, due ~2 Oct 2026)
**Status as of 4 Sep 2026, day 3:** experiment infrastructure complete; all eight modes implemented and validated; the statistical matrix is running.
**Companion documents:** `docs/event-generation-approaches.md` (technical analysis), `docs/implementation-environment.md` (Ch. 5), `docs/experiment-harness.md` (Ch. 6 methodology), `docs/synthetic-dataset.md`, `docs/experiment-c2-design.md`, `docs/fault-matrix-results.md`, `docs/empirical_comparison_results.md`, **`docs/credit-process-observability.md`**, `docs/evidence/R1-logminer-feasibility.md`

---

## 1. The Single Most Important Decision: What Is the Contribution?

A comparison of three known patterns is a **survey**, not a thesis. A survey is defensible at Bachelor's level; a Master's thesis needs a falsifiable claim that did not exist before you made it.

### 1.1 Recommended contribution statement

> **This thesis quantifies, under controlled fault injection on a realistic A1 banking transaction workload, the event-loss, duplication, latency and database-overhead characteristics of three event-generation patterns for Oracle-backed core banking, and derives from those measurements a weighted decision model for selecting a pattern under stated institutional constraints.**

Three claims follow from it, each falsifiable by experiment:

| # | Claim | Falsified by |
|---|---|---|
| **C1** | Application-level event publication without a transactional outbox exhibits a non-zero, measurable event-loss rate under crash and broker-partition faults, while trigger/AQ, outbox and CDC patterns exhibit `LR = 0` under the same faults. | Observing loss in the atomic patterns, or zero loss in the naive one, across ≥ 5 repetitions. |
| **C2** | LogMiner-based CDC overhead scales with the **total redo volume of the database**, not with the write volume of the captured tables — so narrowing the capture scope does **not** proportionally reduce database overhead. | Measuring a proportional drop in DB CPU when `table.include.list` is narrowed at constant total redo. |
| **C3** | A hybrid of the transactional outbox with log-based relay strictly dominates each pure pattern on a weighted criteria model for A1 workflows, and the dominance is sensitive to exactly two assumptions (application-exclusive writes; modifiable application source). | Finding a pure pattern that scores higher under the stated weights, or a third decisive sensitivity. |

**C2 is the most valuable of the three.** It is counter-intuitive, contradicts common practitioner assumption, and is cheap to measure. If time runs short, protect C2.

### 1.2 Secondary contributions (worth a paragraph each, not a chapter)

* A trace-context propagation mechanism (`DBMS_SESSION.SET_CONTEXT`) that makes database-generated events joinable to distributed application traces — closes a correlation gap normally cited as an inherent limitation of database-level capture.
* An explicit demonstration that Spring's transaction-advisor ordering silently degrades a correct outbox implementation to a lossy one, with a runtime assertion that converts the silent failure into a loud one.
* A reproducible fault-injection harness for event-pipeline reliability on Oracle, published with the thesis.

### 1.3 What this thesis is NOT

State the exclusions explicitly in Chapter 1 — examiners reward scope discipline and punish its absence:

* Not a performance study of Oracle, Kafka or Spring in general.
* Not a study of event *consumption*, stream processing frameworks, or downstream analytics.
* Not a formal verification of the delivery semantics; the argument is empirical.
* Not a production deployment; external validity is bounded by the test environment (§7).

---

## 2. Thesis Structure and Current Completion State

| Ch. | Title | Pages | Source material | State |
|---|---|---|---|---|
| 1 | Introduction — problem, relevance, aim, objectives, research questions, contribution, structure | 6–8 | §1 of this plan | **Not started** (correctly — written last but one) |
| 2 | State of the Art | 12–15 | `chapter2-literature-review.md`, `references.bib` | **Protocol and 31 verified sources; no prose.** Still the largest risk |
| 3 | Problem Domain and Requirements — the A1 transaction AND the credit process | 8–10 | `event-generation-approaches.md` §0/§3, **`credit-process-observability.md` §1** | **~75 %** |
| 4 | Design of the Three Approaches | 15–18 | `event-generation-approaches.md` §1 | **~85 % drafted** |
| 5 | Implementation | 10–12 | `implementation-environment.md` (23 findings) + working code | **~90 %** |
| 6 | **Experimental Evaluation of the capture mechanisms** | 15–20 | `empirical_comparison_results.md`, `fault-matrix-results.md`, `experiment-c2-design.md` | **Results complete — 175 cells. Prose ~30 %** |
| 7 | **Process Observability Applied — where the time goes in a credit application** | 10–14 | **`credit-process-observability.md`** | **Analysis complete; prose ~40 %** |
| 8 | Discussion — decision model, hybrid, sensitivity, threats to validity | 10–12 | `event-generation-approaches.md` §4 | **~70 %; three predictions to correct** |
| 9 | Conclusion and Future Work | 3–4 | — | Not started |
| — | References (35–50), Appendices | — | `references.bib` at 31 | ~35 % |

**Chapter 7 is new, and it changes what the thesis is.** Until 10 September the work proved that
events could be captured reliably and quantified what each mechanism cost — but never showed what
the events were *for*. An examiner could reasonably have asked where the observability was in a
thesis about observability. Chapter 7 answers it: the credit application process of an Uzbek bank,
analysed from the stage-transition event log, showing that **1.9 % of a credit application's
elapsed time is anyone at the bank working on it** and that the largest bank-controlled delay is
queueing rather than processing. The mechanism chapters are the means; this is the end, and the
dependency runs one way — none of Chapter 7's numbers survive a pipeline that loses transitions.

**Assessment on 4 September.** The position has inverted since this plan was written. The empirical work — which was the thing at risk — is now the strongest part of the project: the environment is built, all eight modes are implemented and validated end to end, the harness runs one command per experimental cell, and the statistical matrix is executing. What is now weakest is **Chapter 2**, which has not been started at all, and the **formal requirements**, which are still unknown.

On a one-month deadline that inversion is the right one to have — infrastructure cannot be rushed at the end, whereas a literature review can be worked on in parallel with runs that take hours of machine time and no human attention.

---

## 2a. What Actually Exists — Evidence Inventory (4 Sep 2026)

Everything in this section is built, run and archived in the repository. It is the material a supervisor can be shown.

### Environment and data

| Artefact | State |
|---|---|
| Nine-service Docker stack (Oracle 26ai Free 23.26.3, Kafka 4.1 KRaft RF=3, Debezium Connect 3.5.2, Apicurio, Prometheus, Grafana, Kafka UI) | Running; one command brings it up |
| Oracle prepared: ARCHIVELOG, FORCE LOGGING, supplemental logging, capture user with LOGMINING | Verified; assertions raise rather than report false success |
| Flyway migrations V1–V9 | Applied, zero invalid objects |
| Synthetic dataset: 20 000 customers, 33 751 accounts | Generated in-database by `PKG_SYNTH_DATA`. **Contains no personal data of any kind** |
| Spring Boot 4.1.1 / Java 21 application implementing the A1 lifecycle | Running; identical business code in every mode |

**No production bank data is used anywhere in this thesis, by decision.** The dataset contains no names, addresses, dates of birth or identity numbers — only synthetic references of the form `CUST-000000123`, a segment, a branch code and a risk rating. This is a stated scope decision on information-security grounds and belongs in Chapter 1 and in the defence.

### The eight modes, all implemented and validated end to end

| Mode | Approach | Validated |
|---|---|---|
| `OFF` | No instrumentation — true throughput ceiling | yes |
| `BASELINE_GT` | Ground-truth trigger only — measures the cost of the measuring apparatus itself | yes |
| `AQ` | **Approach 1**: compound trigger → `PKG_A1_EVENT` → `DBMS_AQ` (`ON_COMMIT`) → AQ-JMS bridge → Kafka | yes |
| `WRAPPER_B1` | **Approach 2 naive**: publish inside the transaction (dual write, retained to be refuted) | yes |
| `WRAPPER_B2` | **Approach 2**: publish after commit (no phantoms, unprotected loss window) | yes |
| `WRAPPER_B3` | **Approach 2 correct**: AOP → transactional outbox → polling relay | yes |
| `CDC` | **Approach 3**: Debezium mines `TXN_A1` from redo; no application event code at all | yes |
| `HYBRID` | **Recommended**: outbox written in-transaction, relayed by Debezium | yes |

### The harness

One command is one experimental cell, fully archived: `./scripts/run-experiment.sh --mode CDC --profile P1 --rep 3`. Eleven steps from database reset to a row in `results/summary.csv`, so every number in the thesis traces back to the raw data that produced it. `./scripts/run-matrix.sh A` runs the whole matrix, is resumable, interleaves repetitions and rotates mode order so that no mode is confounded with the time of day it ran at.

Reconciliation is against an independent ground truth written by a trigger inside the business transaction, on the key `(txn_id, new_status)` — the only identifier available in every mode.

### Measurements already in hand (pilot runs, n = 1, superseded by the running matrix)

| Mode | latency p50 | redo/transition vs control | HTTP p99 | loss |
|---|---|---|---|---|
| `BASELINE_GT` | — | 4 236 (control) | 18.2 ms | — |
| `AQ` | **7 ms** | +136.6 % | 37.6 ms | 0 |
| `WRAPPER_B3` | 125 ms | +92.6 % | 166 ms | 0 |
| `CDC` | 2 613 ms | ≈ control | 33.6 ms | 0 |
| `HYBRID` | 3 360 ms | +110.5 % | 193 ms | 0 |
| `WRAPPER_B1` | 0 ms, **38.3 % of samples negative** | ≈ control | 361 ms | 0 |
| `WRAPPER_B2` | 2 ms | ≈ control | **7 997 ms** | 0 |

All four complete pipelines delivered every committed transition, in order, exactly once. **At this sample size their reliability is not distinguishable** — which is exactly why the fault matrix, not the clean runs, carries claim C1.

### Findings that were not in the plan and are worth reporting

1. **CDC without per-table ALL-column supplemental logging publishes the right *number* of semantically empty events.** 9 003 messages for 9 003 transitions, all valid JSON, connector healthy, no warning — and two thirds of them carrying `TXN_ID: "0"` and `TXN_REF: ""`. Every count-based validation passes perfectly. Only reconciliation on a semantic key against an independent ground truth exposes it. This is the strongest justification for the thesis's methodology and is a candidate for a paper in its own right.
2. **`WRAPPER_B1` published 38.3 % of its events before the transaction that produced them committed** — a direct, quantified measurement of the dual-write window, rather than the usual qualitative description of it.
3. **`WRAPPER_B2` — the "safe-looking" after-commit variant — raised HTTP p99 to 8 seconds**, because the customer waits for Kafka. Its correctness problem is well known; its latency problem is not usually stated.
4. **Oracle 23ai separated the `LOCK` privilege from `SELECT` (ORA-41900).** Every Debezium-on-Oracle privilege list written before 23ai is now incomplete, and the only grant-based remedy is the system-wide `LOCK ANY TABLE`, which no bank will give a capture account.
5. **Six defects were found by measurement in the harness's own subject**, three of which would have produced a *better-looking* result than the truth. This body of evidence supports promoting "how to validate an event-pipeline benchmark" from a methods paragraph to a named secondary contribution.

### One claim already refuted by measurement

The analysis document's code comment stated that relaying the outbox with Debezium "removes the polling query entirely and cuts end-to-end latency". The first half is true; the second is false by a factor of 27 — the polling relay measured 125 ms and the hybrid 3 360 ms, because Debezium's LogMiner cycle is itself a slower poll. **The claim has been retracted in the source and must be corrected in Chapter 7.** What the hybrid actually buys is coverage of writers that never call the application, and removal of polling load from the OLTP instance — not latency.

---

## 3. Phase Plan

### Phase 0 — Formalisation · **STILL OPEN — now the critical path**

Nothing technical should start before this is signed off. It was not signed off, and the technical work went ahead anyway. That was the right call for a one-month deadline, but the debt is now due: every item below is still outstanding and three of them need the supervisor.

| Task | Output | Done when | State |
|---|---|---|---|
| **Lock the research question and contribution (§1)** | One paragraph, one page of claims C1–C3 | Supervisor agrees in writing | ⬜ **blocking — take to the 4 Sep meeting** |
| **Confirm the university's formal requirements** | Page count, structure, citation style, deadlines, defence format | Written down in this repo | ⬜ **blocking — nobody knows these yet** |
| Write the thesis proposal / plan | 3–5 pages per ITPU template | Submitted | ⬜ |
| Choose the writing toolchain | LaTeX on Overleaf + Zotero (recommended), or Word + Mendeley | First compile succeeds | ⬜ |
| Create the bibliography skeleton | 15–20 seed references imported | `.bib` file in the repo | ⬜ |
| Define the scope exclusions (§1.3) | One page | In the proposal | 🟨 drafted in §1.3; add the no-production-data decision |

**Recommendation on the toolchain:** LaTeX. A 90-page document with 40 code listings, 25 tables and 90 citations is where Word becomes an active obstacle. Overleaf removes the installation problem entirely.

### Phase 1 — Literature Review · **0 % — THE BIGGEST RISK IN THE PROJECT**

The most commonly underestimated phase, and the one that most often causes a weak defence. On a one-month deadline it cannot be left until the experiments finish. It should start today, in parallel: matrix runs take hours of machine time and no human attention, and that is exactly the time to be reading.

| Task | Target |
|---|---|
| Systematic search: IEEE Xplore, ACM DL, ScienceDirect, Google Scholar, arXiv | 60–80 candidates screened |
| Screening by title/abstract → full-text reading | 35–50 cited |
| Grey literature: Debezium/Oracle/Confluent documentation, engineering blogs | 15–25 cited, clearly marked as grey |
| Identify and state the **research gap** explicitly | One paragraph that leads directly to your contribution |
| Write Chapter 2 draft | 12–15 pages |

**Search terms to start with:** `change data capture`, `transactional outbox`, `dual write problem`, `event-driven microservices banking`, `log-based replication Oracle`, `exactly-once semantics stream processing`, `observability distributed transactions`, `database trigger overhead OLTP`, `Debezium evaluation`, `event sourcing financial systems`.

**The gap you are filling, stated for the examiners:** the literature compares these patterns *qualitatively*, or measures throughput only. Controlled, reproducible measurement of **event loss under injected faults** on a realistic banking workload is largely absent. That absence is your opening.

### Phase 2 — Environment and Harness · **COMPLETE (days 1–3)**

Every deliverable below exists and is documented in `docs/implementation-environment.md` and `docs/experiment-harness.md`.

| Task | Output |
|---|---|
| `docker-compose.yml`: Oracle 23ai Free (ARCHIVELOG + supplemental logging), Kafka (KRaft), Kafka Connect + Debezium, Schema Registry, Prometheus, Grafana | One command brings the whole stack up |
| Schema migrations (Flyway): `TXN_A1`, outbox, AQ/TEQ, `GROUND_TRUTH`, heartbeat | `mvn flyway:migrate` succeeds |
| A1 domain model and REST API in Spring Boot | `INITIATED → VALIDATED → PROCESSED` works end to end |
| Load generator (k6 or JMeter) driving the full A1 lifecycle | Sustained 200 TPS reached |
| **Experiment harness**: one script = one run, writes CSV | `./run-experiment.sh --mode CDC --profile P1 --rep 3` |
| Metrics collection: Micrometer, AWR snapshots, Connect JMX, `V$SYSSTAT` deltas | Grafana dashboard shows all four sources |
| Reconciliation job (`GROUND_TRUTH` vs. sink) | Reports `LR`, `DR`, `OVR` for a run |

> **Automate the harness before writing any pattern implementation.** Manual experiment runs are the single most common reason a systems thesis runs out of time. If a run cannot be started, measured and archived by one command, the experiment will not be repeated five times, and without repetition there is no statistics and no Chapter 6.

### Phase 3 — Implementation · **COMPLETE (days 2–3), ahead of plan and in a different order**

The plan proposed building `AQ` last and sacrificing it if late. In the event all eight modes were built, including both refuted wrapper baselines, so nothing needs to be sacrificed. Original ordering retained below for the record:

| Week | Mode | Why this order |
|---|---|---|
| 7 | `OFF` (baseline) + `WRAPPER_B3` (outbox) | Baseline is needed by every comparison; B3 is the recommended pattern |
| 8 | `WRAPPER_B1` + `WRAPPER_B2` | Cheap (small deltas on B3) and produce the headline loss result for C1 |
| 9 | `CDC` (Debezium + LogMiner + enrichment topology) | Needed for C2, the most valuable claim |
| 10 | `AQ` (trigger + queue + JMS bridge) | Highest implementation cost, lowest marginal contribution — sacrifice first if late |

Definition of done per mode: integration test with Testcontainers proving an end-to-end event, a Grafana panel, and a successful harness run recorded in CSV.

### Phase 4 — Experiments · **IN PROGRESS (started day 3)** · THE CORE

| Week | Content |
|---|---|
| 11 | 🟩 **Running now**: 8 modes × profile P1 × 5 repetitions, 50 TPS, 120 s. Produces `ΔTPS`, `ΔP99`, `ΔRedo`, `ΔCPU`, latency percentiles. ~3.5 h of machine time |
| 12 | ⬜ Batch profile P4 (large single transaction, generated in-database — invisible to the wrapper) + idle profile P5 |
| 13 | ⬜ **Phase B of the matrix**: F1, F2, F4, F5, F8, F11 — all implemented in `scripts/inject-fault.sh`, none run yet. **This is what carries claim C1** |
| 14 | 🟨 **Targeted C2 experiment** — designed and instrumented (`docs/experiment-c2-design.md`), **not yet run**. 36 runs, ~3.6 h, after Phase B |

**Minimum viable experiment**, if time collapses: modes `OFF`, `WRAPPER_B1`, `WRAPPER_B3`, `CDC`; profiles P1 and P4; faults F1, F4, F11, F12; 5 repetitions. That is still a complete, defensible Chapter 6.

### Phase 5 — Analysis and Writing · **partially pre-built**

`harness/aggregate.py` already computes medians and IQRs, pools reliability across repetitions for the Rule-of-Three bound, and runs an **exact permutation Mann–Whitney U test** (no `scipy` on this machine, and with n = 5 the normal approximation is not valid anyway). Note the hard limit this imposes: with five repetitions per arm the smallest attainable two-sided p-value is 2/252 = 0.0079, so **no result can be significant beyond that**, and the report says so.

| Week | Content |
|---|---|
| 15 | Statistical analysis (median/IQR, bootstrap CI, Mann–Whitney U, Rule of Three for zero-loss bounds); figures |
| 16 | Chapter 6 written; Chapter 7 updated so every claim points at a measured number |
| 17 | Chapters 3, 4, 5 finalised from the existing draft; Chapter 1 written **last but one** |
| 18 | Chapter 8, abstract, full read-through for internal consistency |

**Write Chapter 1 near the end.** An introduction written before the results promises things the results do not deliver, and the mismatch is exactly what examiners probe.

### Phase 6 — Defence

| Task | Note |
|---|---|
| Supervisor review and revision | Budget a full week; it always takes one |
| Formatting, plagiarism check, university submission | Mechanical but time-consuming |
| Slides: 12–15 for a 15–20 minute talk | Structure: problem → gap → method → **results** → recommendation. Results get half the slides |
| Anticipated questions | See §6 |
| Live demo (optional, high-impact) | The fault-injection run: kill the JVM, show B1 losing an event and B3 not losing one. Two minutes, and it settles the whole argument |

---

## 4. Technical Prerequisites

| Component | Recommendation | Notes |
|---|---|---|
| Oracle | `container-registry.oracle.com/database/free` (23ai Free) | Requires accepting the licence on the Oracle container registry. Confirm ARCHIVELOG, supplemental logging and LogMiner all work in Free edition **in week 5, not week 9** — this is a project-level risk |
| Kafka | KRaft mode, single broker for development, 3 brokers for the F2 fault | RF=3 requires 3 brokers |
| Kafka Connect | Debezium Oracle connector 3.5.x + `ojdbc17` | XStream would need a GoldenGate licence — out of scope; mention OpenLogReplicator only as related work unless you can actually run it |
| Schema Registry | Confluent or Apicurio | Apicurio if licence terms matter |
| Metrics | Prometheus + Grafana + JMX exporter | Also captures Connect metrics |
| Load | k6 (JavaScript, lighter) or JMeter (GUI, familiar) | k6 recommended for scriptable, reproducible runs |
| Analysis | Python + pandas + matplotlib in a Jupyter notebook, committed to the repo | Reproducibility is itself a contribution |
| Writing | Overleaf (LaTeX) + Zotero | IEEE or ACM style unless ITPU mandates otherwise |
| Hardware | ≥ 16 GB RAM, ≥ 8 cores, SSD | Oracle alone wants 4 GB; the full stack is heavy |

---

## 5. Risk Register

| # | Risk | Status on 4 Sep | Evidence |
|---|---|---|---|
| R1 | LogMiner or supplemental logging unavailable in Oracle Free | 🟩 **RETIRED, day 1** | `docs/evidence/R1-logminer-feasibility.md`. Three A1 state transitions recovered from redo at SCN 2307018/2307021/2307024 on Oracle 26ai Free 23.26.3 |
| R2 | Manual experiment runs consume all remaining time | 🟩 **RETIRED, day 2** | Harness built before the remaining modes, deliberately. One command per cell; `run-matrix.sh` runs the matrix unattended and is resumable |
| R3 | Scope explosion | 🟨 **Live, managed** | Phase A is 40 cells; Phase B is 63. Both are bounded and defined in `run-matrix.sh`. The minimum viable experiment remains the fallback |
| R4 | Literature review left until late | 🟥 **THE ACTIVE RISK — 0 % done** | Nothing written. Must start in parallel with the matrix runs, today |
| R5 | Hardware cannot sustain 200 TPS | 🟨 **Materialised, mitigated** | Running at 50 TPS, not 200. `WRAPPER_B2` is the binding constraint — HTTP p99 already 8 s at 50 TPS. Report as a stated limitation; the relative comparison is unaffected |
| R6 | AQ/JMS bridge awkward to obtain or licence | 🟩 **RETIRED, day 3** | `com.oracle.database.messaging:aqapi-jakarta:23.9.0.0` on Maven Central; `AqToKafkaBridge` implemented and validated at 9 003/9 003 with zero loss |
| R7 | Results uninteresting — all modes indistinguishable in steady state | 🟨 **Partly materialised, as predicted** | All four pipelines showed zero loss in clean runs. This was anticipated: the fault matrix carries the argument. Steady state did, however, produce a **480× latency spread** (7 ms to 3 360 ms), which is a result in itself |
| R8 | Supervisor requests a change of direction late | 🟥 **Live** | The contribution statement and C1–C3 have **still not been approved in writing**. Three days of implementation now rest on unapproved claims |
| **R9** | C2 — the claim called "most valuable" — had no experiment behind it | 🟨 **Designed 4 Sep, not yet run** | `docs/experiment-c2-design.md`: falsification conditions fixed in advance, noise generator and wide-scope connector built, analysis validated against synthetic data with known coefficients in both directions. 36 runs, ~3.6 h. Risk is now schedule, not design |
| **R10** | Supplemental logging is a per-table switch that changes what every mode costs | 🟩 **Handled** | `ModeActivator` enables ALL-column logging on exactly the table the active mode captures and disables it elsewhere. Leaving it on would have charged Approach 3's redo cost to every other approach |

## 6. Defence Questions to Prepare For

Prepare a slide or a paragraph for each. These are the questions this specific thesis invites:

1. *"Why is this not simply an engineering comparison — where is the science?"* → C1–C3 are falsifiable claims tested by controlled experiment with statistical treatment; the decision model is the generalisable artefact.
2. *"Your test environment is a laptop container. How do your numbers transfer to a bank's RAC/Exadata?"* → They do not, and the thesis says so. All claims are *relative* between modes measured under identical conditions. §7 states this as a bounded threat to validity.
3. *"You observed zero losses. How can you claim zero?"* → You cannot. You claim an upper bound via the Rule of Three: `LR < 3/n` at 95 % confidence.
4. *"Your recommendation is a known pattern. What is new?"* → The measurement is new, the sensitivity analysis is new, and the C2 finding contradicts a common practitioner assumption.
5. *"Why not use exactly-once semantics?"* → Because end-to-end exactly-once delivery is not achievable across a database and a broker without XA; the achievable property is at-least-once delivery with idempotent effect. Distinguish the two crisply.
6. *"What about the security implications of the CDC capture account?"* → Covered in the analysis; `SELECT ANY TABLE` + `LOGMINING` is unrestricted read on the core database and is a real adoption blocker.
7. *"What would you do differently with more time?"* → Have an honest answer ready. Suggested: mine an Active Data Guard standby; measure OpenLogReplicator; validate the decision model against a second institution's constraints.

---

## 7. Bounded Claims — Write These Down Now

To be reproduced verbatim in Chapters 1 and 7, so that no reader over-reads the results:

* All performance figures are **relative comparisons between modes** measured under identical conditions in a containerised single-instance environment. They are not predictions of production behaviour on RAC or Exadata.
* Loss rates are reported as **one-sided upper bounds** when no loss is observed.
* LOE and maintenance-overhead figures are **structured expert estimates**, not measurements, and are labelled as such wherever they appear.
* The evaluation covers **event generation**, not event consumption, downstream processing, or end-user observability tooling.
* The decision model's weights encode **stated assumptions about institutional priorities**; §3.6's sensitivity analysis shows how the ranking changes when they are varied.

---

## 8. Compressing to 12 Weeks

If the deadline is tighter than 20 weeks, cut in this order — and never cut Phase 4:

| Cut | Weeks saved | Cost |
|---|---|---|
| Drop the `AQ` mode; treat Approach 1 as design-and-analysis only, without measurement | 2 | Chapter 6 covers two patterns instead of three. Acceptable if stated. Frames Approach 1 as related work |
| Drop profiles P2, P3, P5; keep P1 and P4 | 1 | Fewer workload dimensions |
| Reduce fault injection to F1, F4, F11, F12 | 1 | Still covers all three loss mechanisms |
| Reduce repetitions from 5 to 3 | 1 | Weaker confidence intervals; report the limitation |
| Reduce the literature review to 30 cited sources | 1 | **Riskiest cut** — thin Chapter 2 is what examiners notice first |
| Reuse the existing analysis document directly for Chapters 3, 4, 5 with light editing | 2 | Already the plan |

---

## 9. Next Seven Days (5–11 Sep) — Concrete Checklist

Ordered so that machine time and human time run in parallel. The matrix occupies the machine; the literature review occupies the person.

**Blocking, needs the supervisor (do first):**
- [ ] Get the contribution statement (§1.1) and claims C1–C3 **approved in writing** — three days of implementation currently rest on unapproved claims (R8)
- [ ] Obtain ITPU's formal requirements: page count, structure, citation style, exact submission deadline, defence format — **nobody knows these yet**
- [ ] Confirm what "A1" means in the bank's own system: which table, which status values, which transitions. The experiment currently assumes `INITIATED → VALIDATED → PROCESSED` with a `REJECTED` terminal. **This is the last open modelling assumption, and it affects Chapter 3, not the code**

**Machine, unattended:**
- [ ] Phase A matrix completes (~3.5 h) → run `harness/aggregate.py` → first statistically-backed results table
- [ ] Phase B fault matrix (~5 h) → the evidence for claim C1
- [ ] Design and run the C2 experiment (§10.1) — currently unbuilt and the highest-value gap

**Person, in parallel with the above:**
- [ ] Create the Overleaf project and `.bib`; commit the link
- [ ] Import the seed references from `event-generation-approaches.md` Appendix C into Zotero
- [ ] Screen 60–80 candidate papers by title and abstract; read 15 of them
- [ ] Draft the Chapter 2 skeleton with the research gap stated in one paragraph
- [ ] Write the scope-exclusion page, including the no-production-data decision

---

## 10. Agenda for the Supervisor Meeting

### 10.1 Claim C2 — designed; the decision is now whether to spend the machine time

C2 states that LogMiner overhead scales with the **total redo volume of the database**, not with the write volume of the captured tables. It is the most valuable claim in the thesis: counter-intuitive, and it decides whether a bank can put a capture process on a busy core instance.

It now has a full design — `docs/experiment-c2-design.md` — with the falsification conditions fixed **before** any data exists:

* **F-a.** The fitted coefficient on total redo is not significantly greater than zero.
* **F-b.** Widening the capture scope raises database cost in proportion to the captured volume.

**The design in one paragraph.** Two sub-experiments. *C2a* holds the captured A1 workload constant and varies only the redo the connector will discard, written into a table outside `table.include.list` at five paced levels; each level is run twice, with the connector present and absent, so that mining cost is a **difference of differences** against an instance-wide CPU counter — which is what makes it attributable at all, since Debezium recreates its LogMiner session between iterations and a per-session counter would lose its history. *C2b* then varies the capture scope at constant total redo, because scope is the lever a DBA actually has. Two models are fitted to the same points — cost as a function of captured redo alone, versus captured plus total — and the headline number is the **share of database-side capture cost spent on redo that never becomes an event**.

**What is already built:** the noise generator with paced updates against a fixed row pool, session tagging so a generator can never outlive its cell, a wide-scope connector template differing from the narrow one in exactly one key, the `--no-connector` arm, and the analysis. The analysis was validated against synthetic data with known coefficients in both directions: given `a = 40` it recovered 40.01, and given `a = 0` it returned an interval containing zero and reported C2 falsified. An analysis that can only confirm its own hypothesis is not a test.

**Question for the supervisor:** the design is done and the cost is now purely 3.6 hours of unattended machine time on top of Phase B's five. Is that time better spent on C2, or on the literature review? My recommendation is C2 — it is the only claim in the thesis that could surprise an examiner, and the machine time does not compete with reading.

### 10.2 Should the methodological finding become a named contribution?

Six defects were found by measuring the harness against itself. Three of them would have produced a **better-looking** result than the truth:

* CDC without per-table supplemental logging delivered the exact right number of structurally valid, semantically empty events — every count-based check passed.
* A misconfigured outbox router produced a median end-to-end latency of −1 ms, which with the sign flipped would have read as the fastest pipeline ever measured.
* `ROWNUM` applied before `ORDER BY` silently reordered 2.6 % of transactions while losing nothing, so no loss metric could see it.

Taken together these support a claim stronger than a methods paragraph: **counting events does not measure an event pipeline, and a benchmark that cannot detect its own broken apparatus reports the breakage under the system's name.** Whether that is promoted to a named secondary contribution is a supervisor's call.

### 10.3 Claim to correct in Chapter 7

The hybrid was predicted to be the faster of the two Debezium pipelines and measured as the slower (3 360 ms against 2 613 ms), and 27× slower than the polling relay it replaces. The recommendation still stands, but on different grounds: coverage of writers that bypass the application, and removal of polling load from the OLTP instance. The latency argument must be withdrawn.

### 10.4 Confirmations to obtain

| Item | Why it matters |
|---|---|
| No production bank data will be used; all experiments run on synthetic data with no personal data at all | Information-security decision; belongs in Chapter 1 and the defence |
| 50 TPS rather than 200 TPS, with `WRAPPER_B2` as the binding constraint | Stated limitation; the relative comparison is unaffected |
| Zero-loss results reported as Rule-of-Three upper bounds, never as "zero" | Anticipates the obvious examiner question |
| Five repetitions per cell, with p ≥ 0.0079 as the hard floor on significance | Honest statement of what the sample size can and cannot support |
