# Chapter 2 — State of the Art

## Working document: search protocol, screening record, structure, and the gap statement

**Started 4 September 2026.** This is the chapter that was at 0 % and carried the highest risk in
the project. What exists now is a documented search protocol, a screened seed bibliography of 31
verified entries (`docs/references.bib`), and the structure below. What does not yet exist is the
prose.

---

## 1. Search protocol

A literature review is only defensible if someone else can repeat it. The protocol is therefore
recorded before the writing, in the form examiners expect.

### 1.1 Sources

| Source | Status | Note |
|---|---|---|
| **DBLP** | **Searched, 4 Sep 2026** | Computer-science bibliography. Complete for venues, but **indexes titles only** |
| IEEE Xplore | ⬜ pending | Needs university credentials |
| ACM Digital Library | ⬜ pending | Needs university credentials |
| Scopus / Web of Science | ⬜ pending | For citation-count screening and forward search |
| arXiv | ⬜ pending | Pre-prints, especially industrial systems work |
| Grey literature | ⬜ pending | Debezium, Oracle, Confluent, AWS documentation; Richardson's *Microservices Patterns*; Helland's *Data on the Outside versus Data on the Inside*. To be cited and **explicitly labelled as grey** |

### 1.2 Queries executed and their yields

Twenty queries were run against DBLP. The yields are recorded exactly, including the zeroes,
because the zeroes turn out to carry the argument of §4.

| Query | Title matches |
|---|---|
| `change data capture` | 17 |
| `microservice migration monolith` | 18 |
| `distributed tracing microservices` | 14 |
| `publish subscribe reliability` | 13 |
| `event sourcing architecture` | 3 |
| `log-based replication database` | 3 |
| `event-driven microservices architecture` | 3 |
| `observability microservices distributed` | 3 |
| `event streaming Kafka` | 3 |
| `microservices data consistency` | 2 |
| `saga pattern microservices` | 2 |
| **`transactional outbox`** | **0** |
| **`outbox`** | **0** |
| **`dual write consistency microservices`** | **0** |
| **`exactly-once semantics stream processing`** | **0** |
| **`database trigger performance overhead`** | **0** |
| **`database replication log mining`** | **0** |
| **`eventual consistency distributed transactions`** | **0** |
| **`message delivery guarantees middleware`** | **0** |
| **`banking transaction processing system`** | **0** |

### 1.3 What the zeroes do and do not mean

**They must not be over-read, and the thesis will say so explicitly.** DBLP matches on title
text. A zero means *no indexed publication carries that phrase in its title*. It does not mean no
research exists on the topic — work on eventual consistency and on delivery guarantees plainly
exists under other titles, and full-text search in IEEE Xplore and the ACM DL will find some of
it.

What the zeroes do establish is narrower and still useful: **the vocabulary this thesis works in
is practitioner vocabulary, not academic vocabulary.** "Transactional outbox", "dual write" and
"exactly-once" are the terms the industry uses to describe these mechanisms, and no peer-reviewed
title in the largest computer-science bibliography uses them. The patterns are documented in
books, vendor documentation and engineering blogs.

Confirming this properly requires the full-text databases, and that is the first task of the next
session. The claim in the chapter will be calibrated to whatever those searches return.

### 1.4 Screening

59 unique records were returned. Screening applied three criteria:

1. **Topical relevance** to event generation, capture, delivery or observability — excluded, for
   example, a remote-sensing paper that matched only because its title contained "change …
   captured".
2. **Peer-reviewed venue** — DBLP's record types "Conference and Workshop Papers" and "Journal
   Articles" only; informal and withdrawn records dropped.
3. **Verifiable identifier** — a DOI or a resolvable DBLP URL.

31 records survived and are in `docs/references.bib`, grouped by theme. Every entry was written
from the search response; none was reconstructed from memory.

---

## 2. Chapter structure

| § | Section | Sources in hand | Still needed |
|---|---|---|---|
| 2.1 | Observability of distributed systems: logs, metrics, traces, and the gap events fill | 7 | Definitional sources; the "three pillars" framing and its critics |
| 2.2 | Event-driven architecture and the consistency problem | 5 | Helland 2005; Richardson; CAP/BASE foundations |
| 2.3 | Change data capture and log-based replication | 9 | Oracle LogMiner internals; Debezium architecture papers |
| 2.4 | Event sourcing and its performance characteristics | 3 | Sufficient for a short treatment |
| 2.5 | Delivery guarantees in message-oriented middleware | 4 | Kafka's transactional protocol; exactly-once literature |
| 2.6 | Constraints specific to banking and regulated systems | 0 | **The weakest section — needs dedicated searching** |
| 2.7 | Synthesis: what has been measured, and what has not | — | Written last |

### Sources already in hand that carry particular weight

* **Das et al. (2012), "All aboard the Databus!"** — LinkedIn's CDC platform at SoCC. The
  foundational systems paper for log-based capture at scale, and the natural anchor for §2.3.
* **Bação and Guerreiro (2026), "Consistency challenges in event-driven microservices"** — a
  recent literature review on exactly the problem this thesis measures. It defines the space
  §2.2 occupies and is the single most important source to read first.
* **Nõu, Talluri, Iosup et al. (2025), "Investigating Performance Overhead of Distributed
  Tracing"** — methodologically the closest paper to this thesis. It measures the overhead of an
  observability mechanism rather than describing it, which is the same move made here.
* **Ashok et al. (2024), "TraceWeaver: Distributed Request Tracing Without Application
  Modification"** — the non-intrusive argument, which is precisely the argument for Approach 3.
* **Schmidt et al. (2015), "Change data capture in NoSQL databases: A functional and performance
  comparison"** — the nearest existing comparison, and therefore the paper against which this
  thesis's contribution has to be positioned.
* **Esposito et al. (2013), "On reliability in publish/subscribe services"** — the vocabulary for
  §2.5's reliability definitions.

---

## 3. Reading order for the next session

Fifteen papers, in the order that most quickly produces a defensible §2.7:

1. Bação and Guerreiro 2026 — defines the problem space
2. Das et al. 2012 — the CDC anchor
3. Schmidt et al. 2015 — the nearest comparison
4. Nõu et al. 2025 — the methodological model
5. Ashok et al. 2024 — non-intrusive capture
6. Usman et al. 2022 — observability survey
7. Esposito et al. 2013 — reliability definitions
8. Stefanko et al. 2019 — Saga in practice
9. Maddodi et al. 2020 — event sourcing performance
10. Bashtovyi and Fechan 2023 — CDC for migration to event-driven microservices
11. Povzner et al. 2023 — Kora, streaming platform engineering
12. Qu et al. 2021 — workload-aware CDC
13. Shi et al. 2008 — log-based CDC mechanism
14. Laigner et al. 2020 — monolith to event-driven migration
15. Mayer et al. 2012 — pub/sub reliability survey

---

## 4. The gap statement — draft

To be refined once the full-text searches are done. The current draft, calibrated to what the
searches actually support:

> Research on event-driven architecture treats the delivery of state changes largely as a design
> question. The mechanisms available for generating those events from a relational
> database — database triggers with queueing, application-level publication with a transactional
> outbox, and log-based change data capture — are documented in depth in practitioner literature
> and vendor documentation, and are compared there on qualitative grounds: coupling, intrusiveness,
> operational burden. Where quantitative comparison exists, it measures **throughput and
> latency**.
>
> What is largely absent is controlled measurement of **event loss under injected faults**. The
> property that decides whether an event pipeline is fit for a regulated financial system is not
> how fast it runs but whether it can drop a state change without anyone noticing — and that
> property is asserted far more often than it is measured.
>
> This thesis measures it. It reconciles every delivered event against an independent ground
> truth recorded inside the business transaction, under a fault matrix applied identically to
> each mechanism, on a synthetic banking workload. It reports loss as a statistical upper bound
> rather than as an unfalsifiable zero, and it quantifies what each mechanism costs the database
> that hosts it.

### Why the gap is credible rather than convenient

Three observations support it, and the chapter will present all three:

1. **The vocabulary is practitioner vocabulary.** No peer-reviewed title in DBLP contains
   "transactional outbox" or "dual write" (§1.2), subject to the caveat in §1.3.
2. **The nearest existing comparison measures function and throughput, not loss.** Schmidt et al.
   (2015) compare CDC methods across NoSQL databases on functional coverage and performance; loss
   under fault is not part of the evaluation.
3. **The methodological precedent exists in an adjacent field.** Nõu et al. (2025) measure the
   overhead of distributed tracing rather than describing it. This thesis makes the same move for
   event generation, and adds the fault dimension.

---

## 5. Honest assessment of where this chapter stands

**Done:** search protocol recorded and repeatable; 31 verified sources; structure fixed; gap
statement drafted with its evidence identified.

**Not done:** no prose written; §2.6 (banking and regulatory constraints) has **no sources at
all** and is the weakest point; the full-text databases have not been searched, so both the source
count and the strength of the §1.3 claim will change.

**The realistic target** is 35–50 cited sources for a chapter of this scope. 31 is a seed, not a
finished search — and the seed came from one database searching titles only.
