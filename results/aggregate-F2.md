# Matrix aggregate — profile `P1`, fault `F2`

Repetitions per mode: `AQ` = 3, `WRAPPER_B1` = 3, `WRAPPER_B2` = 3, `WRAPPER_B3` = 3, `CDC` = 3, `HYBRID` = 3


## Reliability, pooled across repetitions

| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |
|---|---|---|---|---|---|---|---|---|
| `AQ` | 3 | 81,009 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 37.0 ppm |
| `WRAPPER_B1` | 3 | 80,742 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 37.2 ppm |
| `WRAPPER_B2` | 3 | 80,997 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 37.0 ppm |
| `WRAPPER_B3` | 3 | 81,009 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 37.0 ppm |
| `CDC` | 3 | 81,006 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 37.0 ppm |
| `HYBRID` | 3 | 81,006 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 37.0 ppm |

Duplicate and ordering columns report the WORST run, not the mean: a defect that appears in one repetition out of five is a property of the mechanism, and averaging it away is how an intermittent fault gets written up as absent.


## redo bytes/transition

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 10,235 | 10,224–10,598 | — | — | — |
| `WRAPPER_B1` | 3 | 3,817 | 3,817–3,853 | — | — | — |
| `WRAPPER_B2` | 3 | 3,829 | 3,816–4,045 | — | — | — |
| `WRAPPER_B3` | 3 | 8,443 | 8,335–8,623 | — | — | — |
| `CDC` | 3 | 3,899 | 3,898–3,934 | — | — | — |
| `HYBRID` | 3 | 7,196 | 7,150–7,246 | — | — | — |

## latency p50 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 19,123 | 16,747–19,990 | — | — | — |
| `WRAPPER_B1` | 3 | 0 | 0–0 | — | — | — |
| `WRAPPER_B2` | 3 | 1 | 1–1 | — | — | — |
| `WRAPPER_B3` | 3 | 20,544 | 20,166–22,785 | — | — | — |
| `CDC` | 3 | 3,273 | 3,166–3,484 | — | — | — |
| `HYBRID` | 3 | 3,332 | 3,252–3,456 | — | — | — |

## latency p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 101,298 | 100,972–102,166 | — | — | — |
| `WRAPPER_B1` | 3 | 1 | 1–1 | — | — | — |
| `WRAPPER_B2` | 3 | 2 | 2–2 | — | — | — |
| `WRAPPER_B3` | 3 | 103,087 | 102,158–104,280 | — | — | — |
| `CDC` | 3 | 6,924 | 6,656–7,064 | — | — | — |
| `HYBRID` | 3 | 6,625 | 6,304–6,950 | — | — | — |

## latency p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 109,850 | 108,613–110,407 | — | — | — |
| `WRAPPER_B1` | 3 | 1 | 1–1 | — | — | — |
| `WRAPPER_B2` | 3 | 6 | 5–6 | — | — | — |
| `WRAPPER_B3` | 3 | 110,744 | 110,240–111,460 | — | — | — |
| `CDC` | 3 | 8,549 | 8,346–8,576 | — | — | — |
| `HYBRID` | 3 | 8,065 | 7,760–8,186 | — | — | — |

## HTTP p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 8.36 | 7.06–8.49 | — | — | — |
| `WRAPPER_B1` | 3 | 5.70 | 5.57–6.71 | — | — | — |
| `WRAPPER_B2` | 3 | 6.35 | 6.17–6.40 | — | — | — |
| `WRAPPER_B3` | 3 | 7.88 | 7.84–9.13 | — | — | — |
| `CDC` | 3 | 5.28 | 4.97–5.53 | — | — | — |
| `HYBRID` | 3 | 7.84 | 7.67–8.46 | — | — | — |

## HTTP p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 14.54 | 12.40–15.54 | — | — | — |
| `WRAPPER_B1` | 3 | 73.35 | 44.43–207.69 | — | — | — |
| `WRAPPER_B2` | 3 | 57.92 | 37.35–70.63 | — | — | — |
| `WRAPPER_B3` | 3 | 36.50 | 26.48–40.58 | — | — | — |
| `CDC` | 3 | 9.32 | 8.38–9.36 | — | — | — |
| `HYBRID` | 3 | 18.48 | 17.88–32.99 | — | — | — |

## achieved TPS

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 46.2 | 45.9–46.2 | — | — | — |
| `WRAPPER_B1` | 3 | 45.9 | 45.5–46.1 | — | — | — |
| `WRAPPER_B2` | 3 | 46.2 | 45.9–46.2 | — | — | — |
| `WRAPPER_B3` | 3 | 45.6 | 45.5–45.9 | — | — | — |
| `CDC` | 3 | 45.6 | 45.5–45.9 | — | — | — |
| `HYBRID` | 3 | 46.2 | 46.2–46.2 | — | — | — |

## user commits

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 31,001 | 30,997–31,030 | — | — | — |
| `WRAPPER_B1` | 3 | 27,000 | 26,870–27,006 | — | — | — |
| `WRAPPER_B2` | 3 | 27,007 | 27,004–27,028 | — | — | — |
| `WRAPPER_B3` | 3 | 27,347 | 27,342–27,362 | — | — | — |
| `CDC` | 3 | 27,143 | 27,142–27,146 | — | — | — |
| `HYBRID` | 3 | 27,143 | 27,142–27,152 | — | — | — |

---

Comparisons are against `BASELINE_GT`. The p-value is an exact two-sided permutation test on the Mann-Whitney U statistic; with five repetitions per arm the smallest attainable value is 0.0079, so no result here can be significant beyond that. "shift (H-L)" is the Hodges-Lehmann estimator, the median of all pairwise differences — the magnitude that belongs next to the p-value.

