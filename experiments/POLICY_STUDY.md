# Large v2 policy comparison

The study is configured in `configs/v2-policy-study.json`. Preparation and timing
tests are separate from full-study execution. Both NetLogo model files remain
unchanged. The runner observes intermediate outcomes while preserving NetLogo's
random-number state, so measurement does not alter subsequent trades.

The completed benchmark and [runtime budget](../docs/results/policy-study/index.md)
estimate 12.5 hours for the core comparison, with roughly 20 hours of planning
allowance on this computer. These files record the prelaunch timing budget,
not a live execution status.

## Core design

| Dimension | Specification |
| --- | --- |
| Networks | All 920 public synthetic mutual stated willingness-to-trade graphs |
| Families | Pooled primary generator; corrected hub sensitivity alternative |
| Sizes and graph replication | 2–24 kiosks; 20 graphs per size per family |
| Financial simulation seeds | 20 shared seeds, 11–220 in steps of 11 |
| Policies | Eight nonredundant arms below |
| Horizon | 1,000 ticks |
| Cumulative observations | Ticks 100, 250, 500 and 1,000 |
| Market demand | `2 × kiosk count` requests per tick; unequal traffic remains enabled |
| Total | 147,200 runs: 73,600 per family |
| Execution | 46 serial batches, one family/size per batch, 3,200 runs each |

The eight policies are isolation, external-only, network sharing with 0/50/100%
commission subsidy, and network sharing with external fallback with 0/50/100%
subsidy. Subsidy is a share of a uniform **1% commission**, not the exchanged amount.
Initial liquidity, trading thresholds, reserves, external access, travel, opening
hours and demand heterogeneity retain the pilot assumptions, made explicit in the
config. The fixed per-market demand of the small pilot is replaced by demand
proportional to kiosk count. This is a different demand scenario, so the core
study should not be interpreted as a simple extension of its mean policy effects.

Each graph/seed appears under all eight policies. Graph generation seeds,
bootstrap-fit labels and simulation seeds remain distinct. Empty/disconnected
graphs and duplicate shapes are retained. Different families are not identical
graphs and should not be treated as adjacency-matched policy pairs.

## Prepare, benchmark, estimate

Run from `ABM/`, using Python 3.10+, NetLogo 7.0.3 and Java 11. If Java is not on
PATH, append `--java 'C:/path/to/java.exe' --javac 'C:/path/to/javac.exe'` to commands
that run NetLogo. Install Fetch with `python scripts/install_netlogo_fetch.py` if
needed. All network inputs are the public synthetic library; no surveys are read.

```powershell
python -m unittest discover -s experiments -p 'test_*.py'
python experiments/policy_study.py prepare --out results/v2-policy-study-final
python experiments/policy_study.py benchmark --out results/v2-policy-study-final --benchmark-out results/v2-policy-study-benchmark-final
python experiments/policy_study.py estimate --out results/v2-policy-study-final --benchmark-out results/v2-policy-study-benchmark-final
```

Preparation validates all batches and writes `plan.json` and `batches.csv`; it
executes **zero simulations**. It does not materialize 147,200 run records until
their individual batches are requested. Model, runner, study config and all three
network CSVs are fingerprinted. Changed inputs require a fresh plan/output folder.

The benchmark measures 576 runs: both generators × sizes 2/12/24 × lowest/highest
density graph in each family/size × eight policies × horizons 200/1,000/3,000 ×
two seeds. Its seeded shuffled order spreads warm/JIT effects across workloads.
Two discarded warm-ups precede the batch. Checkpoints and CSV output are enabled
as in the core study, and their cost is included in timing. Do not run other
simulation batches simultaneously while timing.

The estimate uses the **measured 1,000-tick runs**, matching generator and policy,
interpolating between measured sizes and sparse/dense endpoints. Density position
is relative to the available graph ensemble at each size; it is a runtime
approximation, not a model of scientific policy outcomes. Compilation, JVM/model
startup and warm-up overhead are charged once per planned batch. The planning
allowance uses at least 1.5× interpolated run costs and the slowest relevant
measured run. It is not a confidence interval or guaranteed maximum.

`runtime-estimates.json` and `runtime-by-batch.csv` contain total and per-batch
budgets. Sparse/dense endpoints, three sizes and two seeds do not exhaust possible
runtime variation. The 3,000-tick tests reveal longer-horizon costs but do not
change the core horizon. Inspect the estimate before authorizing the full study.

## Execute only after reviewing the budget

Individual batches can be inspected and executed explicitly. For example:

```powershell
# Inspect one complete batch without executing it.
python experiments/policy_study.py run --out results/v2-policy-study-final --batch pooled-n12 --dry-run

# Execute that saved batch only after reviewing the runtime budget.
python experiments/policy_study.py run --out results/v2-policy-study-final --batch pooled-n12 --resume
```

Use IDs from `batches.csv`. Successful run checkpoints survive interruption;
`--resume` retries missing/failed runs under the identical inputs. A dry run creates
the batch directory, so starting it requires `--resume`. Each batch is below the
existing harness's 50,000-run design limit. Run batches serially for these estimates
to apply. Raw designs, runs, logs and trajectories stay in ignored `results/`.

For an authorized full-study run, `scripts/run_policy_study_background.ps1` runs
all 46 batches serially with `--resume`, stops at the first failure and prevents
duplicate supervisors using a file lock. Pass `-Python`, `-Java`, `-Javac` and
`-NetLogoHome` if those executables are not on PATH. `-DryRun` lists batches only.
Launch it with PowerShell's `Start-Process -WindowStyle Hidden` to keep it detached
from the terminal. Live status is `background-status.json` in the study folder;
`background.log` is the supervisor log and each batch has its own `run.log`.
If interrupted, rerun the same supervisor to skip completed run checkpoints.
Keep the computer awake and preserve the fingerprinted inputs until completion.

## Measurements and analysis

`results.csv` contains final metrics; `summary.csv` summarizes the 20 simulation
seeds for each graph/policy. `trajectories.csv` records cumulative metrics at the
four measurement times, including separate deposit/withdrawal service, failures,
closures, peer/external trades, fees and subsidy spending. Per-period outcomes can
be derived from differences in cumulative values/counts; a cumulative percentage
must not itself be differenced to calculate an interval service percentage.

Trajectory rows are written only after a run completes successfully, before its
successful attempt is checkpointed. A crash between those writes may leave
duplicate observations on resume: retain the last complete row for each
`(run_id, tick)` and use only run IDs whose latest attempt succeeded. Torn tails
are preserved separately and removed before appending. Missing trajectories must
not be treated as zero outcomes. Benchmark verification checks every expected
snapshot, final-result agreement, original demand identity and fee accounting.

The observations include startup dynamics; no economic burn-in is silently
discarded. The two JVM warm-ups are separate discarded executions. Pending trades
remain pending at each horizon. Ongoing subsidies add market cash, so stationarity
is not assumed. Per-kiosk customer service inequalities are not measured by the
existing counters; this core study measures market-level service and costs.

Pair policy effects within graph/seed, report graph-level gains/losses and size
strata, and separate the two generators. Simulation seeds and graphs sharing a
bootstrap fit must not be counted as independent empirical markets. Retain the
four bootstrap-fit labels when describing uncertainty. No policy ranking is a
numerical forecast of surveyed markets.

After the core comparison, use targeted factorial follow-ups for travel × closure ×
trigger, external access × delay × hours, and commission × subsidy. These are
separate designs and runtime budgets; the 147,200-run estimate covers the core
comparison only. Site reports should show paired response curves/heatmaps,
defaults, network variation, sponsor spending and the frequency of harmful effects.

The dedicated observation regression check can be rerun in a new local folder:

```powershell
python tests/study_measurement_checks.py --out results/measurement-check-new
```
