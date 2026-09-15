# Matrix aggregate — profile `P1`, fault `F1`

Repetitions per mode: `AQ` = 3, `WRAPPER_B1` = 3, `WRAPPER_B2` = 3, `WRAPPER_B3` = 4, `CDC` = 3, `HYBRID` = 3


## Reliability, pooled across repetitions

| Mode | runs | transitions | missing | phantom | duplicates | OVR | loss rate | 95% upper bound |
|---|---|---|---|---|---|---|---|---|
| `AQ` | 3 | 26,849 | 5 | 0 | 0.0000 | 0.0000 | 186.2 ppm | — |
| `WRAPPER_B1` | 3 | 26,791 | 3 | 0 | 0.0000 | 0.0000 | 112.0 ppm | — |
| `WRAPPER_B2` | 3 | 26,915 | 3 | 0 | 0.0000 | 0.0000 | 111.5 ppm | — |
| `WRAPPER_B3` | 4 | 35,909 | 56 | 0 | 0.0000 | 0.0000 | 1,559.5 ppm | — |
| `CDC` | 3 | 26,935 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 111.4 ppm |
| `HYBRID` | 3 | 26,932 | 0 | 0 | 0.0000 | 0.0000 | 0 observed | < 111.4 ppm |

Duplicate and ordering columns report the WORST run, not the mean: a defect that appears in one repetition out of five is a property of the mechanism, and averaging it away is how an intermittent fault gets written up as absent.


## redo bytes/transition

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 11,033 | 11,015–11,035 | — | — | — |
| `WRAPPER_B1` | 3 | 3,812 | 3,811–3,814 | — | — | — |
| `WRAPPER_B2` | 3 | 4,267 | 4,146–4,531 | — | — | — |
| `WRAPPER_B3` | 4 | 8,328 | 8,216–8,428 | — | — | — |
| `CDC` | 3 | 3,910 | 3,909–3,911 | — | — | — |
| `HYBRID` | 3 | 7,624 | 7,401–7,626 | — | — | — |

## latency p50 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 5 | 5–6 | — | — | — |
| `WRAPPER_B1` | 3 | 0 | 0–0 | — | — | — |
| `WRAPPER_B2` | 3 | 1 | 1–1 | — | — | — |
| `WRAPPER_B3` | 4 | 130 | 125–136 | — | — | — |
| `CDC` | 3 | 3,561 | 3,520–3,720 | — | — | — |
| `HYBRID` | 3 | 3,652 | 3,419–3,658 | — | — | — |

## latency p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 13 | 12–16 | — | — | — |
| `WRAPPER_B1` | 3 | 1 | 1–1 | — | — | — |
| `WRAPPER_B2` | 3 | 3 | 3–3 | — | — | — |
| `WRAPPER_B3` | 4 | 236 | 229–244 | — | — | — |
| `CDC` | 3 | 6,886 | 6,676–7,166 | — | — | — |
| `HYBRID` | 3 | 6,688 | 6,629–6,912 | — | — | — |

## latency p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 1,541 | 1,294–2,804 | — | — | — |
| `WRAPPER_B1` | 3 | 2 | 2–2 | — | — | — |
| `WRAPPER_B2` | 3 | 8 | 8–9 | — | — | — |
| `WRAPPER_B3` | 4 | 1,266 | 1,246–1,356 | — | — | — |
| `CDC` | 3 | 7,859 | 7,690–8,251 | — | — | — |
| `HYBRID` | 3 | 7,881 | 7,745–7,967 | — | — | — |

## HTTP p95 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 6.19 | 6.03–6.82 | — | — | — |
| `WRAPPER_B1` | 3 | 7.19 | 6.47–48.80 | — | — | — |
| `WRAPPER_B2` | 3 | 6.04 | 5.84–6.17 | — | — | — |
| `WRAPPER_B3` | 4 | 6.84 | 6.78–7.24 | — | — | — |
| `CDC` | 3 | 5.16 | 5.15–5.73 | — | — | — |
| `HYBRID` | 3 | 6.71 | 6.64–6.82 | — | — | — |

## HTTP p99 (ms)

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 12.89 | 12.42–23.50 | — | — | — |
| `WRAPPER_B1` | 3 | 327.16 | 194.31–558.61 | — | — | — |
| `WRAPPER_B2` | 3 | 184.52 | 146.90–213.39 | — | — | — |
| `WRAPPER_B3` | 4 | 43.79 | 30.12–63.55 | — | — | — |
| `CDC` | 3 | 10.37 | 9.81–10.44 | — | — | — |
| `HYBRID` | 3 | 34.19 | 28.13–44.31 | — | — | — |

## achieved TPS

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 15.1 | 15.1–15.1 | — | — | — |
| `WRAPPER_B1` | 3 | 15.3 | 15.3–15.3 | — | — | — |
| `WRAPPER_B2` | 3 | 15.2 | 15.1–15.3 | — | — | — |
| `WRAPPER_B3` | 4 | 15.1 | 15.1–15.2 | — | — | — |
| `CDC` | 3 | 15.1 | 15.1–15.3 | — | — | — |
| `HYBRID` | 3 | 15.1 | 15.1–15.3 | — | — | — |

## user commits

| Mode | n | median | IQR | vs reference | shift (H-L) | exact p |
|---|---|---|---|---|---|---|
| `AQ` | 3 | 12,352 | 12,284–12,352 | — | — | — |
| `WRAPPER_B1` | 3 | 8,929 | 8,918–8,944 | — | — | — |
| `WRAPPER_B2` | 3 | 8,982 | 8,976–9,000 | — | — | — |
| `WRAPPER_B3` | 4 | 9,242 | 9,230–9,254 | — | — | — |
| `CDC` | 3 | 9,121 | 9,118–9,122 | — | — | — |
| `HYBRID` | 3 | 9,128 | 9,123–9,139 | — | — | — |

---

Comparisons are against `BASELINE_GT`. The p-value is an exact two-sided permutation test on the Mann-Whitney U statistic; with five repetitions per arm the smallest attainable value is 0.0079, so no result here can be significant beyond that. "shift (H-L)" is the Hodges-Lehmann estimator, the median of all pairwise differences — the magnitude that belongs next to the p-value.

