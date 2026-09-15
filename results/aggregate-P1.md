# Matrix aggregate — profile `P1`, fault `none`

Repetitions per mode: `OFF` = 5, `BASELINE_GT` = 5, `AQ` = 5, `WRAPPER_B1` = 5, `WRAPPER_B2` = 5, `WRAPPER_B3` = 5, `CDC` = 5, `HYBRID` = 5


## Reliability, pooled across repetitions

| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |
|---|---|---|---|---|---|---|---|---|
| `OFF` | 5 | 0 | — | — | — | — | baseline, no pipeline | — |
| `BASELINE_GT` | 5 | 99,072 | — | — | — | — | baseline, no pipeline | — |
| `AQ` | 5 | 89,643 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 33.5 ppm |
| `WRAPPER_B1` | 5 | 89,511 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 33.5 ppm |
| `WRAPPER_B2` | 5 | 89,535 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 33.5 ppm |
| `WRAPPER_B3` | 5 | 90,015 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 33.3 ppm |
| `CDC` | 5 | 90,009 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 33.3 ppm |
| `HYBRID` | 5 | 89,997 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 33.3 ppm |

Duplicate and ordering columns report the WORST run, not the mean: a defect that appears in one repetition out of five is a property of the mechanism, and averaging it away is how an intermittent fault gets written up as absent.


## redo bytes/transition

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `BASELINE_GT` | 5 | 3,874 | 3,806–3,878 | — | — | — |
| `AQ` | 5 | 10,515 | 10,381–10,729 | +171.4 % | 6,641 | **0.0079** |
| `WRAPPER_B1` | 5 | 3,806 | 3,806–3,916 | -1.7 % | -0 | 1.0000 |
| `WRAPPER_B2` | 5 | 3,924 | 3,852–3,943 | +1.3 % | 65 | 0.5476 |
| `WRAPPER_B3` | 5 | 8,153 | 8,148–8,295 | +110.4 % | 4,342 | **0.0079** |
| `CDC` | 5 | 3,901 | 3,890–3,930 | +0.7 % | 56 | 0.0952 |
| `HYBRID` | 5 | 7,128 | 7,113–7,348 | +84.0 % | 3,322 | **0.0079** |

## latency p50 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 5 | 6 | 5–8 | — | — | — |
| `WRAPPER_B1` | 5 | 0 | 0–0 | — | — | — |
| `WRAPPER_B2` | 5 | 1 | 1–1 | — | — | — |
| `WRAPPER_B3` | 5 | 128 | 126–129 | — | — | — |
| `CDC` | 5 | 3,362 | 3,277–3,404 | — | — | — |
| `HYBRID` | 5 | 3,186 | 3,028–3,188 | — | — | — |

## latency p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 5 | 13 | 11–149 | — | — | — |
| `WRAPPER_B1` | 5 | 1 | 1–1 | — | — | — |
| `WRAPPER_B2` | 5 | 2 | 2–3 | — | — | — |
| `WRAPPER_B3` | 5 | 231 | 227–232 | — | — | — |
| `CDC` | 5 | 6,751 | 6,346–6,761 | — | — | — |
| `HYBRID` | 5 | 5,804 | 5,759–6,558 | — | — | — |

## latency p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 5 | 1,017 | 747–1,405 | — | — | — |
| `WRAPPER_B1` | 5 | 1 | 1–1 | — | — | — |
| `WRAPPER_B2` | 5 | 8 | 7–9 | — | — | — |
| `WRAPPER_B3` | 5 | 1,279 | 1,161–1,304 | — | — | — |
| `CDC` | 5 | 8,177 | 7,993–8,326 | — | — | — |
| `HYBRID` | 5 | 7,539 | 7,534–8,256 | — | — | — |

## HTTP p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `OFF` | 5 | 5.13 | 4.88–6.60 | -4.9 % | 0.27 | 0.8413 |
| `BASELINE_GT` | 5 | 5.40 | 4.63–5.42 | — | — | — |
| `AQ` | 5 | 6.95 | 5.99–51.03 | +28.6 % | 1.55 | **0.0317** |
| `WRAPPER_B1` | 5 | 6.34 | 6.07–6.54 | +17.3 % | 1.12 | 0.0556 |
| `WRAPPER_B2` | 5 | 6.65 | 6.24–7.22 | +23.1 % | 1.61 | 0.0556 |
| `WRAPPER_B3` | 5 | 7.04 | 6.58–7.59 | +30.4 % | 1.95 | **0.0079** |
| `CDC` | 5 | 5.22 | 5.09–5.24 | -3.3 % | -0.18 | 0.6905 |
| `HYBRID` | 5 | 7.77 | 7.06–8.13 | +43.8 % | 2.43 | **0.0079** |

## HTTP p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `OFF` | 5 | 10.17 | 8.86–197.26 | +13.6 % | 2.13 | 0.5476 |
| `BASELINE_GT` | 5 | 8.95 | 8.04–10.28 | — | — | — |
| `AQ` | 5 | 16.55 | 14.62–317.79 | +84.9 % | 8.05 | 0.0556 |
| `WRAPPER_B1` | 5 | 101.12 | 95.47–123.33 | +1029.8 % | 90.85 | 0.0952 |
| `WRAPPER_B2` | 5 | 170.69 | 130.21–278.07 | +1807.0 % | 160.42 | **0.0317** |
| `WRAPPER_B3` | 5 | 53.14 | 45.68–69.22 | +493.7 % | 39.11 | 0.1508 |
| `CDC` | 5 | 10.01 | 9.13–10.01 | +11.8 % | 0.68 | 0.8413 |
| `HYBRID` | 5 | 66.45 | 23.86–114.22 | +642.4 % | 17.28 | 0.0952 |

## achieved TPS

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `OFF` | 5 | 45.6 | 45.5–45.6 | -0.0 % | -0.0 | 0.4206 |
| `BASELINE_GT` | 5 | 45.6 | 45.6–46.3 | — | — | — |
| `AQ` | 5 | 45.6 | 45.5–45.6 | -0.0 % | -0.0 | 0.3095 |
| `WRAPPER_B1` | 5 | 45.5 | 45.5–45.5 | -0.0 % | -0.2 | 0.0556 |
| `WRAPPER_B2` | 5 | 45.6 | 45.6–46.6 | -0.0 % | -0.0 | 0.8413 |
| `WRAPPER_B3` | 5 | 45.6 | 45.6–45.6 | -0.0 % | -0.0 | 0.4206 |
| `CDC` | 5 | 45.6 | 45.6–45.6 | -0.0 % | -0.0 | 0.5476 |
| `HYBRID` | 5 | 45.6 | 45.6–46.6 | -0.0 % | -0.0 | 0.6905 |

## user commits

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `OFF` | 5 | 18,008 | 18,003–18,008 | +0.0 % | -3 | 0.7460 |
| `BASELINE_GT` | 5 | 18,008 | 18,003–18,016 | — | — | — |
| `AQ` | 5 | 24,766 | 24,559–24,809 | +37.5 % | 6,658 | 0.1508 |
| `WRAPPER_B1` | 5 | 18,000 | 17,991–18,003 | -0.0 % | -13 | 0.1984 |
| `WRAPPER_B2` | 5 | 18,003 | 17,994–18,007 | -0.0 % | -9 | 0.3413 |
| `WRAPPER_B3` | 5 | 18,539 | 18,533–18,540 | +2.9 % | 530 | 0.1508 |
| `CDC` | 5 | 18,109 | 18,104–18,111 | +0.6 % | 101 | 0.1508 |
| `HYBRID` | 5 | 18,107 | 18,100–18,109 | +0.5 % | 97 | 0.1508 |

---

Comparisons are against `BASELINE_GT`. The p-value is an exact two-sided permutation test on the Mann-Whitney U statistic; with five repetitions per arm the smallest attainable value is 0.0079, so no result here can be significant beyond that. "shift (H-L)" is the Hodges-Lehmann estimator, the median of all pairwise differences — the magnitude that belongs next to the p-value.

