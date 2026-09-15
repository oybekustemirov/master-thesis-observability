# Code Tour — What to Open, and What Each File Proves

A guided walk through the implementation, ordered for a 20-minute demonstration. Each entry
names the file, the one thing to point at inside it, and the claim it supports.

**Totals:** 1 697 lines of Java, 876 lines of Flyway SQL, 2 115 lines of harness (Python, Bash,
k6), 3 300 lines of thesis-grade documentation.

---

## 1. The experiment switch — start here

**`src/main/java/.../config/ObservabilityMode.java`** (84 lines)

One enum, eight modes. Every other design decision in the project hangs off it. Point at three
things:

* `OFF` and `BASELINE_GT` are **two** baselines, not one. Reporting a mode's cost as
  *mode − BASELINE_GT* means the control instrument's own overhead is quantified instead of
  hidden inside every result.
* `supplementalLoggingTable()` — ALL-column supplemental logging is switched **per mode**.
  Leaving it on `TXN_A1` permanently would charge Approach 3's redo cost to every other
  approach, including the baselines.
* `requiresAqTrigger()` / `requiresGroundTruthTrigger()` — trigger state is automated, because
  leaving it to manual operation is how an experiment silently measures two mechanisms at once.

**`src/main/java/.../service/A1TransactionService.java`** (74 lines)

The business logic. The point of this file is that **it is identical in all eight modes**. Any
measured difference is the capture mechanism, never the workload.

---

## 2. Approach 1 — Internal Oracle PL/SQL

**`src/main/resources/db/migration/V5__plsql_event_package.sql`** (136 lines)

* `TRG_TXN_A1_AQ` is a **compound trigger** — it buffers row changes and emits in the
  `AFTER STATEMENT` section, which is what avoids the mutating-table error.
* `visibility => DBMS_AQ.ON_COMMIT` — the defining property of the approach. The message becomes
  visible exactly when the business transaction commits and is rolled back if it does not. No
  dual write, no loss window.
* **Deliberately no exception handler.** Swallowing an error would silently drop an A1 event.
  This is the availability coupling of Approach 1, made explicit in code and measured by fault
  F8.
* The `SELECT JSON_OBJECT(...) INTO ... FROM dual` — `JSON_OBJECT ... RETURNING CLOB` cannot be
  a PL/SQL expression on this release (PLS-00684), so every emitted event pays a mandatory
  PL/SQL→SQL context switch on the OLTP critical path. A real, attributable cost.

**`src/main/java/.../aq/AqToKafkaBridge.java`** (241 lines)

* It is a loop, not a `@JmsListener`, and the class comment explains why: per-message session
  commit would cap the bridge at one record per broker round trip — the exact defect measured
  in `OutboxRelay`. Both relays now batch identically, so the comparison measures the
  mechanisms rather than two implementations of different quality.
* `CompletableFuture.allOf(...).join()` **before** `session.commit()`. Committing first would
  remove the message from the queue while its Kafka send could still fail — reintroducing at
  the bridge the very loss window Approach 1 exists to avoid.

**`src/main/java/.../aq/AqJmsConfiguration.java`**

The DataSource is deliberately **not** a Spring bean. Declaring `@Bean DataSource` disabled
Spring Boot's auto-configuration, the whole application ran with no connection pool, and 56 % of
requests failed with ORA-12516 — which looked exactly like "Advanced Queuing collapses under
load". The comment records it.

---

## 3. Approach 2 — Application-level wrapper

**`src/main/java/.../outbox/EventEmittingAspect.java`** (76 lines)

* `@Order(200)` against `@EnableTransactionManagement(order = 100)` in
  `TransactionalEventingConfiguration`. **That integer is the difference between a correct
  outbox and a lossy one**, and nothing warns you when it is wrong.
* The `TransactionSynchronizationManager.isActualTransactionActive()` assertion turns that
  silent failure into a loud one.

**`src/main/java/.../outbox/OutboxWriter.java`** (61 lines)

`@Transactional(propagation = Propagation.MANDATORY)` — the writer refuses to run without a
caller-supplied transaction. Structurally incapable of the dual write.

**`src/main/java/.../outbox/OutboxRelay.java`** (145 lines) — **the best single file to show**

Two defects found by measurement, both documented in the file:

* `HIGH_WATER_SQL` — **`ROWNUM` is applied before `ORDER BY` in Oracle.** The obvious query
  takes an arbitrary *n* rows and then sorts those, which silently delivered 2.6 % of
  transactions out of order while losing nothing, so no loss metric could detect it. Both
  obvious remedies raise ORA-02014; the working fix is two statements.
* The batching comment — sending and blocking one record at a time made p50 latency 7 416 ms.
  Batching brought it to 128 ms.

**`src/main/java/.../naive/DirectKafkaEventEmitter.java`** and `AfterCommitEventEmitter.java`

The two refuted baselines, faithfully implemented rather than strawmanned. B1 published 38 % of
its events **before** the transaction that produced them committed — the dual-write window,
measured.

---

## 4. Approach 3 — CDC, and the hybrid

**`docker/connect/connectors/cdc.json.tmpl`** (45 lines) and **`hybrid.json.tmpl`** (52 lines)

* `snapshot.locking.mode: none` — Oracle 23ai separated `LOCK` from `SELECT` (ORA-41900), so
  every Debezium privilege list written before 23ai is incomplete. The only grant-based remedy
  is the system-wide `LOCK ANY TABLE`, which no bank gives a capture account.
* In `hybrid.json.tmpl`, the `_comment.timestamp` key records a deleted setting:
  `table.field.event.timestamp` made the hybrid report a **median latency of −1 ms**. With the
  sign flipped it would have read as the fastest pipeline ever measured.
* `key.converter`/`value.converter` are `StringConverter` on the hybrid, so it puts
  **byte-identical payloads** on the bus as the polling relay. The two differ only in transport.

---

## 5. The control instrument

**`src/main/resources/db/migration/V2__ground_truth.sql`** (102 lines)

`TRG_GROUND_TRUTH` writes to `GROUND_TRUTH` inside the same transaction as the business change,
so it is independent of every pipeline under test. This is what makes "was the event lost?" a
question with an answer.

---

## 6. The harness

**`scripts/run-experiment.sh`** (216 lines) — one command, one archived cell

Eleven steps from database reset to a row in `results/summary.csv`. Worth pointing at:

* The settle wait reads the backlog **from the database**, per mode. The earlier version watched
  an outbox-only metric that does not exist in AQ or CDC mode, so those runs verified nothing.
* Step 12 stops the application, because a leftover JVM holds 32 Oracle sessions and the next
  run starts closer to the `processes` ceiling.

**`harness/analyze.py`** (252 lines)

* The reconciliation key `(txn_id, new_status)` — the only identifier available in **every**
  mode, and therefore the only thing that makes the modes comparable.
* Ordering is judged by Kafka partition and offset, not by timestamp: millisecond timestamps tie
  constantly under load and would manufacture violations consumers never observe.
* Negative-latency detection, added after the −1 ms incident.

**`harness/aggregate.py`** (236 lines)

* Reliability is **pooled** across repetitions before bounding — five runs of 18 000 transitions
  is 90 000 trials, and the Rule-of-Three bound tightens from 167 ppm to 33 ppm accordingly.
* An **exact permutation** Mann-Whitney U test, because at n = 5 the normal approximation is not
  valid. The smallest attainable two-sided p is 2/252 = 0.0079, and the report says so.

**`scripts/run-matrix.sh`** — repetitions interleaved, mode order rotated per repetition, so no
mode is confounded with the time of day it ran at.

**`scripts/repair-after-fault.sh`** — F8 replaces `PKG_A1_EVENT` with a broken body and never
restores it; Flyway will not re-apply V8 because it is already recorded as applied. Without this
script every AQ cell after the first F8 would report the previous cell's fault as its own result.

---

## 7. Guardrails worth showing

**`src/main/java/.../harness/EnvironmentAssertions.java`** (61 lines)

Refuses to start a run unless the OLTP DataSource is a pooled `HikariDataSource` of the expected
size. Written after a configuration change silently removed the connection pool and produced a
complete, plausible, entirely fictitious performance catastrophe attributed to Advanced Queuing.

---

## 8. The C2 experiment

**`docs/experiment-c2-design.md`** — falsification conditions fixed **before** any data exists.

**`harness/c2-analyze.py`** (261 lines) — fits the naive and C2 cost models to the same points
and bootstraps the coefficient on total redo. Validated against synthetic data with known
coefficients in **both** directions: given `a = 40` it recovered 40.01; given `a = 0` it returned
an interval containing zero and reported C2 falsified. An analysis that can only confirm its own
hypothesis is not a test.

---

## Suggested 20-minute order

| Minutes | Show | Says |
|---|---|---|
| 0–2 | `docker ps`, the running stack | It is built, not planned |
| 2–5 | `ObservabilityMode.java`, `A1TransactionService.java` | One switch, identical business code |
| 5–9 | `OutboxRelay.java` | Two defects found by measuring, not by reading |
| 9–12 | `V5__plsql_event_package.sql`, `AqToKafkaBridge.java` | Approach 1, and why the bridge is a loop |
| 12–14 | `cdc.json.tmpl`, `hybrid.json.tmpl` | Approach 3, and the −1 ms incident |
| 14–17 | `analyze.py`, `aggregate.py`, `results/aggregate-P1.md` | How a number becomes a result |
| 17–20 | `docs/experiment-c2-design.md` | The decision to be made |
