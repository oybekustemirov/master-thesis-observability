# Matrix aggregate — profile `P1`, fault `F5`

Repetitions per mode: `CDC` = 3, `HYBRID` = 3


## Reliability, pooled across repetitions

| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |
|---|---|---|---|---|---|---|---|---|
| `CDC` | 3 | 233,718 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 12.8 ppm |
| `HYBRID` | 3 | 233,799 | 44976 | 0 | 0.0000 | 0.0000 | 192,370.4 ppm | — |

Duplicate and ordering columns report the WORST run, not the mean: a defect that appears in one repetition out of five is a property of the mechanism, and averaging it away is how an intermittent fault gets written up as absent.


## redo bytes/transition

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 3,936 | 3,840–3,966 | — | — | — |
| `HYBRID` | 3 | 6,457 | 6,437–6,541 | — | — | — |

## latency p50 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 3,783 | 3,688–3,818 | — | — | — |
| `HYBRID` | 3 | 3,300 | 3,236–3,407 | — | — | — |

## latency p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 6,477 | 6,419–7,805 | — | — | — |
| `HYBRID` | 3 | 6,547 | 5,930–6,814 | — | — | — |

## latency p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 8,430 | 8,264–8,924 | — | — | — |
| `HYBRID` | 3 | 8,047 | 6,988–8,114 | — | — | — |

## HTTP p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 4.56 | 4.42–5.09 | — | — | — |
| `HYBRID` | 3 | 7.39 | 6.51–8.65 | — | — | — |

## HTTP p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 6.50 | 6.47–45.06 | — | — | — |
| `HYBRID` | 3 | 14.29 | 11.63–84.06 | — | — | — |

## achieved TPS

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 45.8 | 45.8–47.8 | — | — | — |
| `HYBRID` | 3 | 45.8 | 45.8–47.9 | — | — | — |

## user commits

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `CDC` | 3 | 63,302 | 63,192–63,332 | — | — | — |
| `HYBRID` | 3 | 63,309 | 63,250–63,310 | — | — | — |

---

Comparisons are against `BASELINE_GT`. The p-value is an exact two-sided permutation test on the Mann-Whitney U statistic; with five repetitions per arm the smallest attainable value is 0.0079, so no result here can be significant beyond that. "shift (H-L)" is the Hodges-Lehmann estimator, the median of all pairwise differences — the magnitude that belongs next to the p-value.

