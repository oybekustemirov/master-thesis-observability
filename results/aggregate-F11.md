# Matrix aggregate — profile `P1`, fault `F11`

Repetitions per mode: `AQ` = 3, `WRAPPER_B3` = 3, `CDC` = 3, `HYBRID` = 3


## Reliability, pooled across repetitions

| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |
|---|---|---|---|---|---|---|---|---|
| `AQ` | 3 | 260,970 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 11.5 ppm |
| `WRAPPER_B3` | 3 | 260,952 | 179949 | 0 | 0.0000 | 0.0000 | 689,586.6 ppm | — |
| `CDC` | 3 | 260,982 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 11.5 ppm |
| `HYBRID` | 3 | 260,973 | 179970 | 0 | 0.0000 | 0.0000 | 689,611.6 ppm | — |

Duplicate and ordering columns report the WORST run, not the mean: a defect that appears in one repetition out of five is a property of the mechanism, and averaging it away is how an intermittent fault gets written up as absent.


## redo bytes/transition

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 9,562 | 9,557–9,587 | — | — | — |
| `WRAPPER_B3` | 3 | 4,611 | 4,581–4,616 | — | — | — |
| `CDC` | 3 | 3,398 | 3,395–3,401 | — | — | — |
| `HYBRID` | 3 | 4,363 | 4,354–4,383 | — | — | — |

## latency p50 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 7,940 | 7,874–8,271 | — | — | — |
| `WRAPPER_B3` | 3 | 144 | 142–146 | — | — | — |
| `CDC` | 3 | 5,757 | 5,435–6,356 | — | — | — |
| `HYBRID` | 3 | 3,390 | 3,281–3,594 | — | — | — |

## latency p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 12,184 | 12,100–12,258 | — | — | — |
| `WRAPPER_B3` | 3 | 253 | 252–256 | — | — | — |
| `CDC` | 3 | 9,463 | 8,254–9,624 | — | — | — |
| `HYBRID` | 3 | 6,932 | 6,758–7,212 | — | — | — |

## latency p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 12,933 | 12,793–13,142 | — | — | — |
| `WRAPPER_B3` | 3 | 1,142 | 1,128–2,649 | — | — | — |
| `CDC` | 3 | 9,972 | 9,422–10,394 | — | — | — |
| `HYBRID` | 3 | 8,142 | 8,067–8,431 | — | — | — |

## HTTP p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 7.38 | 7.16–7.63 | — | — | — |
| `WRAPPER_B3` | 3 | 7.10 | 6.83–7.51 | — | — | — |
| `CDC` | 3 | 5.04 | 4.80–5.34 | — | — | — |
| `HYBRID` | 3 | 7.05 | 6.97–7.51 | — | — | — |

## HTTP p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 96.23 | 86.70–96.82 | — | — | — |
| `WRAPPER_B3` | 3 | 51.66 | 50.76–56.02 | — | — | — |
| `CDC` | 3 | 10.15 | 9.71–11.00 | — | — | — |
| `HYBRID` | 3 | 53.66 | 51.59–60.31 | — | — | — |

## achieved TPS

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 45.5 | 45.5–45.9 | — | — | — |
| `WRAPPER_B3` | 3 | 45.5 | 45.4–45.9 | — | — | — |
| `CDC` | 3 | 46.2 | 45.9–46.2 | — | — | — |
| `HYBRID` | 3 | 46.2 | 45.9–46.2 | — | — | — |

## user commits

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 34,660 | 34,638–34,908 | — | — | — |
| `WRAPPER_B3` | 3 | 27,773 | 27,766–27,776 | — | — | — |
| `CDC` | 3 | 27,149 | 27,148–27,158 | — | — | — |
| `HYBRID` | 3 | 27,145 | 27,144–27,147 | — | — | — |

---

Comparisons are against `BASELINE_GT`. The p-value is an exact two-sided permutation test on the Mann-Whitney U statistic; with five repetitions per arm the smallest attainable value is 0.0079, so no result here can be significant beyond that. "shift (H-L)" is the Hodges-Lehmann estimator, the median of all pairwise differences — the magnitude that belongs next to the p-value.

