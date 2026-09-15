# Matrix aggregate — profile `P1`, fault `F11B`

Repetitions per mode: `WRAPPER_B3` = 3, `HYBRID` = 3


## Reliability, pooled across repetitions

| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |
|---|---|---|---|---|---|---|---|---|
| `WRAPPER_B3` | 3 | 260,550 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 11.5 ppm |
| `HYBRID` | 3 | 260,289 | 62231 | 0 | 0.0000 | 0.0000 | 239,084.2 ppm | — |

Duplicate and ordering columns report the WORST run, not the mean: a defect that appears in one repetition out of five is a property of the mechanism, and averaging it away is how an intermittent fault gets written up as absent.


## redo bytes/transition

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `WRAPPER_B3` | 3 | 7,749 | 7,714–7,790 | — | — | — |
| `HYBRID` | 3 | 6,578 | 6,561–6,585 | — | — | — |

## latency p50 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `WRAPPER_B3` | 3 | 15,789 | 13,590–17,530 | — | — | — |
| `HYBRID` | 3 | 11,918 | 11,078–12,078 | — | — | — |

## latency p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `WRAPPER_B3` | 3 | 23,594 | 19,916–23,619 | — | — | — |
| `HYBRID` | 3 | 18,529 | 17,861–19,885 | — | — | — |

## latency p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `WRAPPER_B3` | 3 | 23,824 | 20,242–24,114 | — | — | — |
| `HYBRID` | 3 | 20,259 | 19,138–21,780 | — | — | — |

## HTTP p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `WRAPPER_B3` | 3 | 190.27 | 143.53–198.97 | — | — | — |
| `HYBRID` | 3 | 102.73 | 67.93–186.82 | — | — | — |

## HTTP p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `WRAPPER_B3` | 3 | 605.36 | 536.04–769.08 | — | — | — |
| `HYBRID` | 3 | 558.86 | 441.61–2,014.66 | — | — | — |

## achieved TPS

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `WRAPPER_B3` | 3 | 49.9 | 49.6–50.0 | — | — | — |
| `HYBRID` | 3 | 49.7 | 49.4–49.8 | — | — | — |

## user commits

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `WRAPPER_B3` | 3 | 27,536 | 27,338–27,550 | — | — | — |
| `HYBRID` | 3 | 26,953 | 26,770–27,041 | — | — | — |

---

Comparisons are against `BASELINE_GT`. The p-value is an exact two-sided permutation test on the Mann-Whitney U statistic; with five repetitions per arm the smallest attainable value is 0.0079, so no result here can be significant beyond that. "shift (H-L)" is the Hodges-Lehmann estimator, the median of all pairwise differences — the magnitude that belongs next to the p-value.

