# Matrix aggregate — profile `P1`, fault `F1R`

Repetitions per mode: `AQ` = 3, `WRAPPER_B1` = 3, `WRAPPER_B2` = 3, `WRAPPER_B3` = 3, `CDC` = 3, `HYBRID` = 3


## Reliability, pooled across repetitions

| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |
|---|---|---|---|---|---|---|---|---|
| `AQ` | 3 | 26,908 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 111.5 ppm |
| `WRAPPER_B1` | 3 | 26,856 | 2 | 0 | 0.0000 | 0.0000 | 74.5 ppm | — |
| `WRAPPER_B2` | 3 | 26,298 | 3 | 0 | 0.0000 | 0.0000 | 114.1 ppm | — |
| `WRAPPER_B3` | 3 | 26,528 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 113.1 ppm |
| `CDC` | 3 | 26,900 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 111.5 ppm |
| `HYBRID` | 3 | 26,564 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 112.9 ppm |

Duplicate and ordering columns report the WORST run, not the mean: a defect that appears in one repetition out of five is a property of the mechanism, and averaging it away is how an intermittent fault gets written up as absent.


## redo bytes/transition

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 11,191 | 10,856–11,647 | — | — | — |
| `WRAPPER_B1` | 3 | 3,852 | 3,846–4,501 | — | — | — |
| `WRAPPER_B2` | 3 | 3,884 | 3,873–3,965 | — | — | — |
| `WRAPPER_B3` | 3 | 8,762 | 8,617–8,804 | — | — | — |
| `CDC` | 3 | 3,953 | 3,948–4,052 | — | — | — |
| `HYBRID` | 3 | 7,208 | 7,205–7,445 | — | — | — |

## latency p50 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 9 | 8–9 | — | — | — |
| `WRAPPER_B1` | 3 | 0 | 0–0 | — | — | — |
| `WRAPPER_B2` | 3 | 2 | 2–2 | — | — | — |
| `WRAPPER_B3` | 3 | 156 | 149–164 | — | — | — |
| `CDC` | 3 | 3,412 | 3,162–3,500 | — | — | — |
| `HYBRID` | 3 | 2,982 | 2,969–3,125 | — | — | — |

## latency p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 122 | 69–333 | — | — | — |
| `WRAPPER_B1` | 3 | 1 | 1–1 | — | — | — |
| `WRAPPER_B2` | 3 | 6 | 5–10 | — | — | — |
| `WRAPPER_B3` | 3 | 1,037 | 644–1,164 | — | — | — |
| `CDC` | 3 | 5,334 | 5,249–5,536 | — | — | — |
| `HYBRID` | 3 | 5,315 | 5,012–5,320 | — | — | — |

## latency p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 1,911 | 1,666–2,018 | — | — | — |
| `WRAPPER_B1` | 3 | 2 | 2–2 | — | — | — |
| `WRAPPER_B2` | 3 | 19 | 16–28 | — | — | — |
| `WRAPPER_B3` | 3 | 2,328 | 1,806–2,550 | — | — | — |
| `CDC` | 3 | 6,161 | 6,010–6,261 | — | — | — |
| `HYBRID` | 3 | 5,887 | 5,870–6,982 | — | — | — |

## HTTP p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 8.88 | 8.08–9.07 | — | — | — |
| `WRAPPER_B1` | 3 | 7.01 | 6.99–9.37 | — | — | — |
| `WRAPPER_B2` | 3 | 9.99 | 9.35–76.96 | — | — | — |
| `WRAPPER_B3` | 3 | 10.88 | 9.69–96.42 | — | — | — |
| `CDC` | 3 | 7.94 | 7.52–8.58 | — | — | — |
| `HYBRID` | 3 | 17.97 | 14.03–75.76 | — | — | — |

## HTTP p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 47.43 | 34.30–56.21 | — | — | — |
| `WRAPPER_B1` | 3 | 432.31 | 317.09–469.48 | — | — | — |
| `WRAPPER_B2` | 3 | 782.79 | 576.78–2,931.92 | — | — | — |
| `WRAPPER_B3` | 3 | 285.63 | 179.26–1,345.05 | — | — | — |
| `CDC` | 3 | 21.42 | 19.97–54.82 | — | — | — |
| `HYBRID` | 3 | 241.00 | 237.97–1,374.36 | — | — | — |

## achieved TPS

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 16.6 | 16.6–16.6 | — | — | — |
| `WRAPPER_B1` | 3 | 16.6 | 16.5–16.6 | — | — | — |
| `WRAPPER_B2` | 3 | 16.5 | 16.1–16.5 | — | — | — |
| `WRAPPER_B3` | 3 | 16.5 | 16.2–16.6 | — | — | — |
| `CDC` | 3 | 16.6 | 16.6–16.6 | — | — | — |
| `HYBRID` | 3 | 16.6 | 16.3–16.6 | — | — | — |

## user commits

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 12,335 | 12,330–12,403 | — | — | — |
| `WRAPPER_B1` | 3 | 8,946 | 8,938–8,990 | — | — | — |
| `WRAPPER_B2` | 3 | 8,891 | 8,678–8,926 | — | — | — |
| `WRAPPER_B3` | 3 | 9,151 | 9,008–9,198 | — | — | — |
| `CDC` | 3 | 9,138 | 9,130–9,144 | — | — | — |
| `HYBRID` | 3 | 9,125 | 8,958–9,134 | — | — | — |

---

Comparisons are against `BASELINE_GT`. The p-value is an exact two-sided permutation test on the Mann-Whitney U statistic; with five repetitions per arm the smallest attainable value is 0.0079, so no result here can be significant beyond that. "shift (H-L)" is the Hodges-Lehmann estimator, the median of all pairwise differences — the magnitude that belongs next to the p-value.

