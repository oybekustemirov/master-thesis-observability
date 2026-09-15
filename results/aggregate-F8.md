# Matrix aggregate — profile `P1`, fault `F8`

Repetitions per mode: `AQ` = 3


## Reliability, pooled across repetitions

| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |
|---|---|---|---|---|---|---|---|---|
| `AQ` | 3 | 26,980 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 111.2 ppm |

Duplicate and ordering columns report the WORST run, not the mean: a defect that appears in one repetition out of five is a property of the mechanism, and averaging it away is how an intermittent fault gets written up as absent.


## redo bytes/transition

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 12,228 | 12,191–12,485 | — | — | — |

## latency p50 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 7 | 6–8 | — | — | — |

## latency p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 17 | 16–34 | — | — | — |

## latency p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 1,318 | 1,254–1,343 | — | — | — |

## HTTP p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 7.64 | 7.12–8.64 | — | — | — |

## HTTP p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 16.10 | 15.82–32.38 | — | — | — |

## achieved TPS

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 15.4 | 15.4–15.4 | — | — | — |

## user commits

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 12,219 | 12,216–12,246 | — | — | — |

---

Comparisons are against `BASELINE_GT`. The p-value is an exact two-sided permutation test on the Mann-Whitney U statistic; with five repetitions per arm the smallest attainable value is 0.0079, so no result here can be significant beyond that. "shift (H-L)" is the Hodges-Lehmann estimator, the median of all pairwise differences — the magnitude that belongs next to the p-value.

