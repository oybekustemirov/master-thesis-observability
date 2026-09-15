# Experiment C2 — results

Cost is instance CPU with the connector present minus the same workload with it absent, at each noise level. Both arms carry identical capture configuration, including supplemental logging, so only the connector differs.


## Measured cost by noise level

| Level | runs on/off | redo total (GB) | redo captured (GB) | redo discarded (GB) | CPU on (s) | CPU off (s) | **mining cost (s)** | events | A1 TPS |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 3/3 | 0.099 | 0.099 | 0.000 | 24.5 | 20.0 | **4.5** | 27,003 | 50.0 |
| 1 | 3/3 | 0.462 | 0.099 | 0.364 | 31.9 | 20.7 | **11.2** | 27,003 | 50.0 |
| 2 | 3/3 | 0.827 | 0.099 | 0.728 | 36.1 | 22.8 | **13.4** | 27,003 | 50.0 |
| 3 | 3/3 | 1.568 | 0.099 | 1.469 | 49.9 | 25.6 | **24.3** | 27,000 | 50.0 |
| 4 | 3/3 | 2.948 | 0.098 | 2.850 | 46.8 | 34.3 | **12.6** | 7,934 | 49.6 |

## Admissibility of each level

| Level | events delivered / committed | ON vs OFF total redo | A1 TPS | verdict |
|---|---|---|---|---|
| 0 | 27,003 / 27,003 (100 %) | 0.10 vs 0.10 GB (2 % apart) | 50.0 | **admissible** |
| 1 | 27,003 / 27,003 (100 %) | 0.46 vs 0.46 GB (0 % apart) | 50.0 | **admissible** |
| 2 | 27,003 / 27,003 (100 %) | 0.83 vs 0.83 GB (0 % apart) | 50.0 | **admissible** |
| 3 | 27,000 / 27,003 (100 %) | 1.57 vs 1.55 GB (1 % apart) | 50.0 | **admissible** |
| 4 | 7,934 / 26,790 (30 %) | 2.95 vs 2.90 GB (2 % apart) | 49.6 | **excluded** — connector did not keep up |

4 of 5 levels admissible.


## The test

**C2a holds captured redo CONSTANT by design** — that is the manipulation. A model with both `redo_total` and `redo_captured` as regressors is therefore unidentifiable here: the second has almost no variance to estimate from. The two hypotheses instead make different predictions about a single slope:

* **Naive** — cost is driven by what is captured. Captured is constant, so **cost should be flat across noise levels**: slope zero.
* **C2** — cost is driven by what is scanned. **Cost should rise with discarded redo**: slope greater than zero.

| quantity | value |
|---|---|
| slope — CPU-seconds per GB of **discarded** redo | **13.01** |
| 95 % bootstrap CI | 5.86 … 18.62 |
| intercept — cost at zero discarded redo | 5.02 s |
| levels in fit | 0, 1, 2, 3 |

**C2 survives falsification condition F-a.** The slope on discarded redo is positive with its interval excluding zero: the database pays measurably for redo the connector reads and throws away. At the highest admissible level (1.47 GB discarded) that accounts for roughly **79 % of the total database-side capture cost**, against a captured volume that never changed.

---

## C2b — does narrowing the capture scope reduce cost?

| Arm | total redo (GB) | CPU (s) | mining cost (s) | events delivered | A1 TPS |
|---|---|---|---|---|---|
| connector absent (baseline) | 2.90 | 34.3 | — | 0 / 26,589 (0 %) | 49.2 |
| narrow — TXN_A1 only | 3.68 | 72.8 | 38.5 | 26,205 / 26,508 (99 %) | 48.5 |
| wide — TXN_A1 + REDO_NOISE | 1.75 | 47.7 | 13.4 | 13,355 / 21,738 (61 %) | 37.8 |

**C2b is inconclusive: its control failed.** The design requires total redo to be identical in both arms, and it was not — 3.68 GB narrow against 1.75 GB wide, **52 % apart**. A1 throughput also diverged, 48.5 against 37.8 TPS.

The wide arm's lower measured cost (13.4 s against 38.5 s) is therefore **not** evidence that a wider scope is cheaper. It did less work: mining the noise table slowed the instance enough that the noise generator could not sustain its rate, so the arm that was supposed to carry identical redo carried half as much. **Falsification condition F-b remains untested.**

What the arm does show, as an operating-envelope observation rather than a test: adding a high-volume table to `table.include.list` cost this instance 22 % of its OLTP throughput and left the connector delivering 61 % of committed events inside the settle window.
