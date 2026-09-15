# Matrix aggregate — profile `P1`, fault `F4R`

Repetitions per mode: `CDC` = 3, `HYBRID` = 3


## Reliability, pooled across repetitions

| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |
|---|---|---|---|---|---|---|---|---|
| `CDC` | 3 | 135,009 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 22.2 ppm |
| `HYBRID` | 3 | 133,848 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 22.4 ppm |

Duplicate and ordering columns report the WORST run, not the mean: a defect that appears in one repetition out of five is a property of the mechanism, and averaging it away is how an intermittent fault gets written up as absent.


## redo bytes/transition

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 4,007 | 3,986–4,013 | — | — | — |
| `HYBRID` | 3 | 7,238 | 7,237–7,367 | — | — | — |

## latency p50 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 3,860 | 3,856–3,889 | — | — | — |
| `HYBRID` | 3 | 3,917 | 3,876–4,016 | — | — | — |

## latency p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 64,211 | 61,712–65,501 | — | — | — |
| `HYBRID` | 3 | 63,946 | 61,588–67,020 | — | — | — |

## latency p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 75,800 | 73,210–77,058 | — | — | — |
| `HYBRID` | 3 | 78,661 | 74,685–79,817 | — | — | — |

## HTTP p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 8.21 | 7.56–9.11 | — | — | — |
| `HYBRID` | 3 | 16.65 | 13.46–92.02 | — | — | — |

## HTTP p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 17.61 | 17.17–19.85 | — | — | — |
| `HYBRID` | 3 | 312.62 | 170.32–1,828.79 | — | — | — |

## achieved TPS

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 50.0 | 50.0–50.0 | — | — | — |
| `HYBRID` | 3 | 49.5 | 49.4–49.8 | — | — | — |

## user commits

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 45,199 | 45,199–45,202 | — | — | — |
| `HYBRID` | 3 | 44,796 | 44,615–45,022 | — | — | — |

---

Comparisons are against `BASELINE_GT`. The p-value is an exact two-sided permutation test on the Mann-Whitney U statistic; with five repetitions per arm the smallest attainable value is 0.0079, so no result here can be significant beyond that. "shift (H-L)" is the Hodges-Lehmann estimator, the median of all pairwise differences — the magnitude that belongs next to the p-value.

