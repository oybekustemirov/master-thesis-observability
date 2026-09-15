# Matrix aggregate — profile `P1`, fault `F4`

Repetitions per mode: `CDC` = 3, `HYBRID` = 3


## Reliability, pooled across repetitions

| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |
|---|---|---|---|---|---|---|---|---|
| `CDC` | 3 | 81,006 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 37.0 ppm |
| `HYBRID` | 3 | 81,006 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 37.0 ppm |

Duplicate and ordering columns report the WORST run, not the mean: a defect that appears in one repetition out of five is a property of the mechanism, and averaging it away is how an intermittent fault gets written up as absent.


## redo bytes/transition

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 3,918 | 3,913–4,010 | — | — | — |
| `HYBRID` | 3 | 7,211 | 7,196–7,212 | — | — | — |

## latency p50 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 6,088 | 6,080–6,268 | — | — | — |
| `HYBRID` | 3 | 5,151 | 5,130–5,269 | — | — | — |

## latency p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 82,352 | 81,213–82,802 | — | — | — |
| `HYBRID` | 3 | 76,666 | 75,912–76,690 | — | — | — |

## latency p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 89,446 | 88,330–89,917 | — | — | — |
| `HYBRID` | 3 | 83,510 | 82,804–83,536 | — | — | — |

## HTTP p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 5.50 | 5.44–5.65 | — | — | — |
| `HYBRID` | 3 | 8.24 | 7.78–8.78 | — | — | — |

## HTTP p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 13.67 | 12.83–15.97 | — | — | — |
| `HYBRID` | 3 | 18.52 | 16.47–23.03 | — | — | — |

## achieved TPS

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 46.2 | 45.9–46.2 | — | — | — |
| `HYBRID` | 3 | 46.2 | 45.9–46.2 | — | — | — |

## user commits

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 27,104 | 27,102–27,110 | — | — | — |
| `HYBRID` | 3 | 27,116 | 27,114–27,120 | — | — | — |

---

Comparisons are against `BASELINE_GT`. The p-value is an exact two-sided permutation test on the Mann-Whitney U statistic; with five repetitions per arm the smallest attainable value is 0.0079, so no result here can be significant beyond that. "shift (H-L)" is the Hodges-Lehmann estimator, the median of all pairwise differences — the magnitude that belongs next to the p-value.

