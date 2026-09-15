# Credit Process Observability

## Chapter 7 source material — what the captured events are for

Chapters 5 and 6 answer a question about *means*: which mechanism captures every state change of a
transaction reliably, and what does each cost the database. That work is complete — 175 archived
experimental cells, three claims tested, three predictions refuted.

This chapter answers the question about *ends*. A bank does not install event capture to admire
its delivery guarantees. It installs it to find out where the time goes in a process that a
customer is waiting on. This is that analysis, performed on the credit application workflow of an
Uzbek bank, entirely from the stage-transition event log.

**The link between the two halves is not decorative.** Every figure below is a difference between
two timestamps. If one transition is lost, the case appears to have skipped a stage and the
duration of the previous one is silently inflated — and no amount of care in the analysis can
detect it, because the arithmetic still works and the chart still renders. The mechanism
comparison exists to establish which capture approach can be trusted not to do that.

---

## 1. The process modelled

Stages follow the process description supplied by the thesis author for Uzbek retail and corporate
credit. They are held in the table `CREDIT_STAGE` rather than in an enum or a check constraint, so
that replacing them with a specific bank's stages is configuration rather than a schema change.

| # | Stage | Type | What the case is waiting for |
|---|---|---|---|
| 1 | `ARIZA_KIRITISH` | HUMAN | A credit specialist to enter the application (10–30 min of work) |
| 2 | `HUJJAT_KUTISH` | CUSTOMER | The applicant to supply documents |
| 3 | `TASHQI_TEKSHIRUV` | AUTOMATED | Scoring, KBI, MIB and tax checks — seconds, unless a state system stalls |
| 4 | `GAROV_BAHOLASH` | **EXTERNAL** | A valuation company to inspect the property (1–3 working days) |
| 5 | `ANDERRAYTER` | HUMAN | An underwriter — 1–5 bank days for collateralised and large loans |
| 6 | `QOMITA_KUTISH` | **COMMITTEE** | The credit committee to sit — Tuesdays and Thursdays at 14:00 |
| 7 | `QOMITA_QARORI` | HUMAN | The committee's decision itself |
| 8 | `SUGURTA_NOTARIUS` | **EXTERNAL** | Insurance and the E-Notarius encumbrance (1 working day) |
| 9 | `SHARTNOMA` | CUSTOMER | The applicant and guarantors to sign |
| 10 | `AJRATISH` | HUMAN | Operations to disburse |
| — | `QAYTARILDI` | HUMAN | Rework: the committee returned the case for insufficient documents |

### 1.1 Two stage types that a queue model cannot express

Most process analyses recognise three kinds of time: automated, working, and queued. This process
needs five, and the two extra ones account for **37 % of the elapsed calendar**.

**`COMMITTEE` — waiting for a room, not for a person.** The credit committee sits twice a week. An
application that finishes underwriting on Tuesday at 14:30 has missed that day's sitting and waits
until Thursday. Nobody is busy; the committee is simply not convened. Modelling this as a queue
would be actively misleading, because **queue time falls when capacity rises and committee time
does not move at all** until somebody schedules another sitting. The only lever is a management
decision, and an analysis that hides it inside "queue" hides the lever too.

**`EXTERNAL` — blocked on a third party.** Collateral valuation is performed by a valuation
company that sends someone to the property; KBI, MIB and tax checks run against state systems.
The bank is neither working nor queuing. Calling this bank queue time would credit the bank with a
problem it cannot fix by hiring; calling it customer time would excuse it from one it can fix, by
choosing a different valuer or negotiating a turnaround.

---

## 2. Where the time goes

5 000 applications over 120 days, 40 127 stage events.

| Whose time | Hours | Share |
|---|---|---|
| **Bank queue — nobody touching the case** | 392 031 | **34.8 %** |
| Waiting on the applicant | 289 785 | 25.7 % |
| External party — valuation, notary, state systems | 267 001 | 23.7 % |
| **Committee calendar** | 150 082 | **13.3 %** |
| **Bank staff actually working** | **21 622** | **1.9 %** |
| Automated processing | 5 424 | 0.5 % |

**1.9 % of the elapsed time in a credit application is anyone at the bank working on it.**

That single number reframes what an improvement programme should target. The remaining 98 % is
waiting, and it divides into four kinds with four different remedies: capacity for the queue,
document policy for the applicant, procurement for the external parties, and a calendar decision
for the committee.

### 2.1 By stage

| Stage | Type | Median queue | Median work | Total hours |
|---|---|---|---|---|
| Anderrayter tekshiruvi | HUMAN | **25.5 h** | 1.9 h | 237 332 |
| Hujjatlarni kutish | CUSTOMER | — | 19.2 h | 226 705 |
| Garov baholash | EXTERNAL | — | 68.1 h | 204 364 |
| Qo'mita yig'ilishini kutish | COMMITTEE | — | 41.8 h | 150 082 |
| Mablag' ajratish | HUMAN | 15.2 h | 0.45 h | 93 246 |
| Ariza kiritish | HUMAN | 9.5 h | 0.28 h | 81 823 |
| Sug'urta va notarius | EXTERNAL | — | 22.0 h | 62 637 |
| Shartnoma imzolash | CUSTOMER | — | 8.9 h | 50 597 |
| Qaytarilgan arizalar | HUMAN | — | 20.7 h | 13 287 |
| Tashqi tekshiruv | AUTOMATED | — | 0.09 h | 5 351 |

---

## 3. The finding that changes what should be done

**Underwriting is the largest single stage, and it is not slow.** It takes 27.5 hours at the
median, of which **1.9 hours is an underwriter working** and 25.5 hours is the case sitting in a
queue.

The spread between underwriters is real: 1.3 hours for the fastest against 3.9 for the slowest, a
factor of 3.1. But that spread is worth **two and a half hours**, while every case waits an
average of **25.6 hours** before anyone opens it.

> A tooling programme aimed at making underwriters faster is optimising the 1.9 %. Capacity and
> queue policy are the 34.8 %.

This is the kind of conclusion that only a queue/work decomposition can support. A report that
said "underwriting takes 27.5 hours" would be true, would sound like a productivity problem, and
would send the effort to the wrong place.

---

## 4. Collateral, not credit type, is the dividing line

| Product | Collateral | Applications | Median days | p90 days | UW queue | Committee wait |
|---|---|---|---|---|---|---|
| Korporativ | yes | 327 | 15.10 | 23.27 | 51.0 h | 43.4 h |
| Biznes | yes | 952 | 13.96 | 23.11 | 49.3 h | 41.8 h |
| Ipoteka | yes | 921 | 13.62 | 22.30 | 49.2 h | 42.6 h |
| Mikroqarz | yes | 703 | 11.50 | 18.39 | 17.9 h | 27.5 h |
| **Mikroqarz** | **no** | **2 097** | **4.42** | **8.79** | 18.9 h | — |

A microloan without collateral closes in 4.42 days. **The same product with collateral takes
11.50 — 2.6 times longer**, and the three collateralised products cluster between 13.6 and 15.1
days regardless of which product they are.

The driver is not the credit type. It is whether there is collateral, because collateral triggers
three additional stages — valuation, the notarial encumbrance, and (in this model) the committee.
Reporting a single "average credit application" duration would describe none of these five
populations.

---

## 5. Rework is invisible in every stage average

1 335 of 5 000 applications — **27 %** — had documents returned at least once.

| | Applications | Median days | p90 days |
|---|---|---|---|
| Clean first pass | 3 665 | 6.82 | 16.40 |
| Documents returned at least once | 1 335 | **12.57** | 22.33 |

**84 % longer.** And no stage average shows it, because each individual pass through a stage looks
entirely normal — the underwriter's second review takes as long as a first one would.

Rework is only visible when the event log carries a **case identifier** and the analysis follows
one application across its whole path. This is the concrete reason the event log must be keyed on
the case rather than aggregated per stage at source, and it is a requirement that falls straight
out of the process rather than out of any technical preference.

A returned application also waits for the committee **again** — the calendar delay is paid twice.

---

## 6. Outcomes

| Outcome | Applications | Share | Median days | p90 days |
|---|---|---|---|---|
| Ajratildi | 3 780 | 75.6 % | 10.32 | 19.05 |
| Rad etildi | 1 026 | 20.5 % | 2.65 | 8.99 |
| Mijoz voz kechdi | 194 | 3.9 % | 11.05 | 22.32 |

Rejections close in a quarter of the time of approvals, which is the desirable direction: 14 % of
applications are rejected at the external checks before anyone has spent working time on them.

Withdrawals are the uncomfortable number. **An applicant who withdraws has waited as long as one
who succeeds** — 11.05 days against 10.32. They sat through the entire process and then left,
which means the process spent its full cost on them and the bank has nothing to show for it.

---

## 7. Why this depends on the mechanism chapters

Every number here is a difference between two timestamps on stage transitions. Three properties of
the capture mechanism decide whether those numbers mean anything:

**It must not lose transitions.** A lost transition does not produce an error; it produces a case
that appears to have skipped a stage, with the previous stage's duration silently inflated by the
missing interval. The clean-run measurements bound loss at under 33 ppm for every complete
pipeline, and the fault matrix establishes which of them keep that property when something breaks.

**It must see writers that are not the application.** Fault F11 drove a batch that writes directly
in PL/SQL, as an end-of-day process or an adjacent system would. The trigger and the redo log
captured all of it; the application-level outbox captured **none** of it — 69 % of transitions
lost. A credit process touched by state-system integrations, batch jobs and back-office tools —
which is every real one — cannot be measured through a mechanism that only sees what one
application does. Fault F11B then showed the outbox recovering complete coverage once the batch
writes through the shared contract, so the property is achievable; it is just conditional on every
writer being changed.

**It must not slow the process it is measuring.** Approach 3 adds nothing detectable to the
transaction path. Approach 1 adds 171 % to redo and, under fault F8, an invalid capture trigger
failed 40 % of business transactions outright. An observability mechanism that stops payments is
not observability.

---

## 8. Assumptions, stated

Everything in this chapter is generated data. The structure is taken from the process description;
the durations are assumptions calibrated to the ranges in it.

* **No personal data of any kind.** Applicants are references of the form `CUST-000000123`; staff
  are an identifier, a role and a branch. Real bank data is not used anywhere in this thesis, on
  information-security grounds.
* **Stage durations are log-normal**, right-skewed, with medians calibrated to the stated ranges:
  underwriting 1–5 bank days by product, valuation 1–3 days, notary 1 day, application entry
  10–30 minutes. They are parameters of a generator, not measurements of a bank.
* **Queues advance in working hours** (Mon–Fri, 09:00–18:00). Without this, queue figures are
  dominated by nights and weekends and report a staffing problem where none exists.
* **The committee sits Tuesday and Thursday at 14:00**, held in `CREDIT_COMMITTEE_SCHEDULE` so the
  analysis can be re-run against a different sitting frequency to price the decision.
* **The findings that matter follow from the process structure, not the parameters.** That
  committee batching dominates, that the underwriter's own work is a fraction of the underwriting
  stage, that collateral rather than product decides duration, and that rework is invisible in
  stage averages — none of these depends on the exact medians chosen. Changing them changes the
  magnitudes and not the conclusions.
* **The `MONITORING` stage — maqsadli ishlatilish monitoringi — is defined but not generated.**
  It is a recurring post-disbursement activity rather than a stage on the path to disbursement,
  and it needs its own model. Noted as remaining work rather than quietly omitted.

---

## 9. Files

| Path | Purpose |
|---|---|
| `src/main/resources/db/migration/V12` | Stage, staff, application and event-log tables |
| `src/main/resources/db/migration/V15` | The Uzbek stage model and committee schedule |
| `src/main/resources/db/migration/V16` | `PKG_CREDIT_PROCESS` — the generator |
| `harness/sql/credit-process-analysis.sql` | The five analyses, spooled as CSV |
| `results/credit/` | Stage summary, outcomes, ownership, rework, actors, by-product |
