# Matrix aggregate — profile `P1`, fault `F5R`

Repetitions per mode: `CDC` = 3, `HYBRID` = 3


## Reliability, pooled across repetitions

| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |
|---|---|---|---|---|---|---|---|---|
| `CDC` | 3 | 233,994 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 12.8 ppm |
| `HYBRID` | 3 | 233,247 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 12.9 ppm |

Duplicate and ordering columns report the WORST run, not the mean: a defect that appears in one repetition out of five is a property of the mechanism, and averaging it away is how an intermittent fault gets written up as absent.


## redo bytes/transition

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 4,450 | 4,444–4,532 | — | — | — |
| `HYBRID` | 3 | 7,109 | 7,076–7,110 | — | — | — |

## latency p50 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 3,852 | 3,787–3,859 | — | — | — |
| `HYBRID` | 3 | 3,664 | 3,618–3,738 | — | — | — |

## latency p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 10,171 | 9,797–12,080 | — | — | — |
| `HYBRID` | 3 | 13,338 | 13,223–14,202 | — | — | — |

## latency p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 11,646 | 11,233–13,528 | — | — | — |
| `HYBRID` | 3 | 15,614 | 15,496–16,198 | — | — | — |

## HTTP p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 5.88 | 5.73–6.09 | — | — | — |
| `HYBRID` | 3 | 12.15 | 10.49–56.34 | — | — | — |

## HTTP p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 16.01 | 15.75–16.02 | — | — | — |
| `HYBRID` | 3 | 69.35 | 55.10–1,435.85 | — | — | — |

## achieved TPS

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 50.0 | 50.0–50.0 | — | — | — |
| `HYBRID` | 3 | 50.0 | 49.7–50.0 | — | — | — |

## user commits

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 63,322 | 63,320–63,346 | — | — | — |
| `HYBRID` | 3 | 63,289 | 62,942–63,294 | — | — | — |

---

Comparisons are against `BASELINE_GT`. The p-value is an exact two-sided permutation test on the Mann-Whitney U statistic; with five repetitions per arm the smallest attainable value is 0.0079, so no result here can be significant beyond that. "shift (H-L)" is the Hodges-Lehmann estimator, the median of all pairwise differences — the magnitude that belongs next to the p-value.

