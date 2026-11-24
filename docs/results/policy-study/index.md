---
title: Large policy study and runtime budget
---

# Large policy study and runtime budget

[Project](../../) · [Experiment dashboard](../) · [Small policy pilot](../policy-pilot/)

This page records the core study design and its prelaunch runtime budget.
Fresh performance tests estimate about **12.5 hours** of serial execution on this
computer, with a **roughly 20-hour planning allowance**. These are runtime
estimates, not policy findings or guaranteed completion times.

## Prepared comparison

The design uses all 920 public synthetic mutual stated willingness-to-trade
networks: 20 draws at every size from 2–24 kiosks, from both the pooled primary
generator and corrected hub alternative. Each graph is tested under eight
policies and 20 simulation seeds for 1,000 ticks, producing **147,200 runs**.

Policies are isolation, external-only rebalancing, network sharing with 0/50/100%
commission subsidy, and sharing with external fallback with 0/50/100% subsidy.
The fee is a uniform 1%; subsidies cover a share of that fee. Market demand is
two requests per kiosk per tick on average, retaining uneven traffic and request
sizes. The other illustrative assumptions are specified in the
[study configuration](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/configs/v2-policy-study.json).

Policies are paired on identical graph/seed combinations. Cumulative measurements
at ticks 100, 250, 500 and 1,000 reveal trajectories as well as final outcomes.
The runner preserves random-number state during observation; a headless regression
check verified that adding intermediate measurements leaves final results unchanged.
Neither NetLogo model file was changed.

## Measured performance

The November 24, 2026 benchmark completed **576/576 runs** and verified **2,112
intermediate snapshots**. It crossed both generators, sizes 2/12/24, sparse/dense
endpoint graphs, all eight policies, three horizons and two seeds. Cases were
shuffled with a fixed seed. Execution used Java 11 and NetLogo 7.0.3 on Windows.

| Horizon | Measured runs | Mean run time | Slowest run |
| --- | ---: | ---: | ---: |
| 200 ticks | 192 | 0.107 s | 0.467 s |
| 1,000 ticks | 192 | 0.298 s | 0.697 s |
| 3,000 ticks | 192 | 0.735 s | 1.777 s |

Run times include setup, simulation, measurement and trajectory output. The whole
benchmark took **228.2 seconds (3.8 minutes)**, including compilation, JVM/model
startup and two discarded warm-ups. Accounting checks passed. Requested customer
counts and values matched across policies, fee ledgers reconciled, every expected
snapshot was present and final snapshots matched final metrics.

## Full-study budget

| Study portion | Runs | Estimated hours | Planning allowance, hours |
| --- | ---: | ---: | ---: |
| Pooled primary networks | 73,600 | 6.34 | 10.01 |
| Corrected hub alternative | 73,600 | 6.13 | 9.84 |
| Combined | 147,200 | 12.47 | 19.85 |

Execution is split into **46 resumable batches of 3,200 runs**, one generator/size
per batch. Estimated batch times range from about **6.5–26.4 minutes**, with
planning allowances of **9.9–39.5 minutes**. A single batch was dry-run validated;
that dry run did not execute NetLogo. These timing files are not a live run status.

Estimates use the measured **1,000-tick** costs, matching policy and generator,
and interpolate between benchmark sizes and their relative sparse/dense positions.
Startup and warm-up overhead is charged once per batch. The allowance uses at
least 1.5 times interpolated costs and the slowest relevant measured run. It is
not a confidence interval or runtime ceiling. Unmeasured topology, background load,
storage and long-duration execution can change costs; no parallel speedup is assumed.

This budget replaces the pilot-based extrapolation: it uses the actual study
horizon, proportional-demand setting and measurement overhead. It covers the
core eight-policy comparison, not later targeted factorial studies. Benchmark
graphs were selected for performance coverage, not to estimate policy effects.

[Download runtime estimates](runtime-estimates.json) ·
[Download per-batch budgets](runtime-by-batch.csv) ·
[Preparation, benchmark and batch instructions](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/POLICY_STUDY.md)

Raw runs, trajectories and logs remain local in ignored directories. Only
synthetic aggregate timings and batch budgets are included here.
