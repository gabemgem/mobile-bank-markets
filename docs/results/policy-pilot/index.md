---
title: Liquidity policy pilot
---

# Liquidity policy pilot

[Project overview](../../) · [Experiment dashboard](../) · [Run this pilot](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/POLICY_PILOT.md)

Network sharing and external rebalancing improved average customer service in this
small synthetic sample. Subsidy effects were smaller and uneven, and some networks
performed worse with sharing or external fallback. These are mechanism tests under
illustrative assumptions, not forecasts for surveyed markets.

## Policies and service

The pilot completed **324 of 324 runs**: six synthetic networks, three seeds,
18 combinations and 200 ticks per run. The table shows the eight distinct active
policies; duplicate control settings are excluded from these averages.
Each row averages the same 18 graph/seed pairs. “Value served” is the percentage
of requested deposit/withdrawal value completed, not the percentage of requests.

| Policy | Fee subsidized | Value served | Change from isolated | Closed kiosk-time | Sponsor spending |
| --- | ---: | ---: | ---: | ---: | ---: |
| Isolated | 0% | 32.17% | — | 0.00% | 0 |
| External only | 0% | 35.40% | +3.22 pp | 13.47% | 0 |
| Network sharing | 0% | 37.51% | +5.34 pp | 14.91% | 0 |
| Network sharing | 50% | 37.76% | +5.59 pp | 14.66% | 534 |
| Network sharing | 100% | 37.50% | +5.33 pp | 15.10% | 1,184 |
| Network + external fallback | 0% | 39.49% | +7.32 pp | 24.03% | 0 |
| Network + external fallback | 50% | 39.95% | +7.78 pp | 23.73% | 692 |
| Network + external fallback | 100% | 40.22% | +8.04 pp | 24.06% | 1,470 |

Sponsor spending is mean settled cash spending per 200-tick run, in arbitrary model
units. A subsidy covers the stated share of a **1% commission**, not that share of
the whole exchange. Sponsor payments add cash to the market as well as reducing
requester costs. External rebalancing exchanges cash for e-float; it is not a grant.

Sharing-only service rose by about 0.25 percentage points at 50% subsidy but was
essentially unchanged at full subsidy. With external fallback, half/full subsidy
added about 0.46/0.72 percentage points relative to unsubsidized fallback. A larger
subsidy is not guaranteed to improve service: trading decisions, travel closures
and evolving balance distributions can change together. These small averages do
not establish a robust subsidy ranking or cost-effectiveness.

## Network differences matter

Values below average three seeds, with no subsidy. The network labels identify
public pooled-ERGM synthetic draws of **mutual stated willingness-to-trade ties**,
not observed trading activity or measured kiosk locations.

| Synthetic graph | Links | Components | Isolated | External only | Network | Network + external |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| pooled-n08-r01 | 4 | 4 | 32.03% | 32.62% | 32.38% | 29.56% |
| pooled-n08-r02 | 14 | 2 | 32.03% | 32.62% | 38.42% | 38.67% |
| pooled-n16-r01 | 36 | 2 | 32.58% | 35.48% | 46.91% | 46.71% |
| pooled-n16-r02 | 9 | 9 | 32.58% | 35.48% | 30.90% | 35.92% |
| pooled-n24-r01 | 11 | 15 | 31.91% | 38.09% | 41.75% | 45.69% |
| pooled-n24-r02 | 5 | 20 | 31.91% | 38.09% | 34.72% | 40.41% |

For example, sharing alone reduced service in `pooled-n16-r02`, while the combined
policy reduced service relative to isolation in `pooled-n08-r01`. Time spent closed
and balance reservations can offset the benefit of a refill. The pilot records
these mechanisms but does not isolate which caused each loss. A follow-up that
crosses travel time with the shop-closure switch would help distinguish them.

Across the 18 graph/seed pairs, the SD of the sharing-only improvement was **7.17
percentage points**; for unsubsidized sharing plus external fallback it was **7.50**.
This is descriptive variation, not a standard error or confidence interval. Graph
draws at a given size reuse the same demand seeds, so the pairs are not independent
market observations. More graph draws should precede strong policy conclusions.

## Assumptions held fixed

| Setting | Value |
| --- | --- |
| Graphs | First two pooled-generator draws at 8, 16 and 24 kiosks |
| Repeats and horizon | Seeds 11, 22, 33; 200 ticks; two discarded warm-ups |
| Initial balances | 500 cash and 500 e-float per kiosk |
| Low-balance trigger / target / outgoing reserve | 25% / 50% / 100 units |
| Peer participation | 100% when enabled |
| Peer commissions | Uniform 1%; no bargaining or credit |
| Geometry | Fixed spring layout; grid size 5; Manhattan travel; requester closes |
| External access | 50% random assignment, fixed for a run |
| External timing and capacity | 3 travel + 1 service ticks; open 8 of 12 ticks; cap 500 per swap; no shared queue limit |
| Demand | 40 market requests per tick; base amounts uniform 1–100 |
| Demand differences | Traffic log-SD 1; size log-SD 0.5; withdrawal share 0.5; polarization 0.35 |

Graph, seed and original requests are matched across policies. Market demand is
fixed rather than demand per kiosk, so the size rows are different workloads,
not an isolated experiment on market size. A tick is a batch of requests, with
no calibrated mapping to minutes. The network sample is small and was selected
by draw number, not to represent the distribution of markets. Synthetic spring
positions can change when graph topology changes.

## Performance before scaling up

Timing was measured on this Windows computer using serial Java 11 / NetLogo 7.0.3
execution on November 24, 2026. Each wall time includes compilation, model/JVM
startup, two warm-ups, simulation and metric extraction.

| Batch | Measured runs | Ticks per run | Wall time |
| --- | ---: | ---: | ---: |
| General v2 random-network benchmark | 24 | 50 and 200 | 14.6 s |
| Actual policy-setting timing sample | 72 | 200 | 18.2 s |
| Policy pilot | 324 | 200 | 38.8 s |

Before the pilot, the policy timing sample predicted **51.9 seconds**, with a
**113.8-second planning allowance**. The following estimates use that same timing
sample, including setup and startup overhead. They do not use the faster pilot
to retroactively improve the prediction.

| Planned runs | Ticks per run | Estimated time | Planning allowance |
| --- | ---: | ---: | ---: |
| 1,000 | 200 | 2.4 min | 5.6 min |
| 10,000 | 200 | 22.4 min | 54.2 min |
| 1,000 | 1,000 | 7.8 min | 19.0 min |
| 10,000 | 1,000 | 76.2 min | 188.1 min |

These apply to similar small graphs and policy settings on this computer. The
1,000-tick rows extrapolate simulation time linearly from 200 ticks. Longer-run
activity, graph structure and background load can change costs. The allowance
uses the larger of 1.5× mean run cost and the slowest measured run cost; it is not
a confidence bound or guaranteed maximum. Rebenchmark at the intended horizon
and workload before a large study. No large sweep was run.

## Checks and reproducibility

All runs completed, with model accounting checks and **180 equivalent/inactive
policy checks**. Original requested counts and values matched across policies
for every graph/seed; supplier fee income equaled requester payments plus sponsor
spending. Pending exchanges remain pending at the 200-tick endpoint.

The [pilot config](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/configs/v2-policy-pilot.json),
[timing config](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/configs/v2-policy-timing.json)
and [run guide](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/POLICY_PILOT.md)
specify the experiment. The model SHA-256 is
`b41a5457f6d4e7176dfbbbef8d3b2557210974358d73a9ae3300d09b5e6ca7d3`.
The model and Java runner were not changed for this study.

[Download aggregate policy results](policy-summary.csv) ·
[Download runtime estimates](runtime-estimates.json)

Raw runs and logs stay local. This page contains only aggregates from the already
public synthetic network library; no survey records, fitted objects or private
market networks are included. The abstract model remains unchanged.
