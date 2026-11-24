# Small v2 policy pilot

The prepared pilot compares peer sharing, external rebalancing and commission
subsidies using public synthetic **mutual stated willingness-to-trade** networks.
It changes no simulation code. Both model files remain unchanged.

## Design

`configs/v2-policy-pilot.json` specifies 324 runs: six graphs × 18 policy cells ×
three seeds (11, 22, 33), each for 200 ticks. Two discarded warm-ups precede each
batch. Graphs are the first two pooled-generator draws at each of 8, 16 and 24
kiosks. They are a small convenience sample, not representative markets. The
corrected-hub generator is left for a subsequent sensitivity study.

The factorial crosses:

- Sharing: **No sharing** or **Network sharing**.
- External mode: **Disabled**, **External only** or **Peers then external**.
- Commission subsidy: **0%, 50% or 100%** of a uniform 1% peer fee.

This produces eight distinct active policies plus deliberately redundant controls.
External-only disables peers regardless of the sharing selector. Subsidies must
have no effect without peer trading. No-sharing with external fallback should
match external-only. The report checks these equivalences rather than treating
duplicate settings as additional scientific replicates.

All kiosks participate in peer sharing when enabled; 50% have randomly assigned
external access. The provider is open 8 of every 12 ticks, with travel 3 + service
1 tick and a 500-unit exchange cap. Grid size is 5 and travel closes the requester.
Each kiosk starts with 500 cash and 500 e-float; trigger/target are 25%/50% and
outgoing reserve is 100. Market demand is 40 requests per tick, maximum base
request 100, withdrawal share 0.5, polarization 0.35, traffic heterogeneity 1 and
size heterogeneity 0.5. All settings are explicit in the config and saved design.

Identical graph/seed pairs retain the same original customer requests, layout and
external access assignments across policies. Compare policies within those pairs.
Demand is held fixed **per market**, so size comparisons also change demand per
kiosk. Two graph draws and three seeds cannot support precise policy estimates.

## Run timing tests first

Run in PowerShell from `ABM`, with Python 3.10+, NetLogo 7.0.3 and a Java 11 JDK.
Install Fetch once with `python scripts/install_netlogo_fetch.py` if needed.
If Java is not on PATH, append `--java 'C:/path/to/java.exe' --javac 'C:/path/to/javac.exe'`
to the two execution commands below.

```powershell
# General v2 benchmark: 24 measured runs, two warm-ups, 50/200-tick horizons.
python experiments/performance.py --model-version v2 --ticks 50 200 --repeats 2 --out results/v2-performance-new

# Actual policy settings: 72 measured runs and two warm-ups at 200 ticks.
python experiments/run_experiments.py experiments/configs/v2-policy-timing.json --out results/v2-policy-timing-new

# Inspect the pilot's count and runtime estimate before launching it.
python experiments/policy_pilot_report.py results/v2-policy-timing-new --out results/v2-policy-plan-new
```

The policy timing config uses the same settings and policies on `pooled-n16-r01`
and `pooled-n24-r01`, with seeds 11 and 22. Only setup, metric extraction and
simulation costs are scaled; JVM/compilation and warm-up costs are included once.
The planning allowance uses the larger of 1.5× mean run cost and the slowest
measured run cost. It is not a statistical confidence interval or runtime ceiling.

The general benchmark's `--profile` estimator intentionally rejects imported
networks. Use `policy_pilot_report.py` for this pilot. Its estimates apply only to
similar 8–24-kiosk graphs and the measured policy settings. A future config with
more graph draws/seeds or a longer horizon can be supplied with `--plan PATH`;
changing financial/demand/travel settings requires a fresh matching timing config.
Longer horizons extrapolate linearly from 200 ticks and need a longer timing test
before a substantial study. The harness runs serially.

## Run and check the pilot

```powershell
python experiments/run_experiments.py experiments/configs/v2-policy-pilot.json --out results/v2-policy-pilot-new
python experiments/policy_pilot_report.py results/v2-policy-timing-new --pilot results/v2-policy-pilot-new --out results/v2-policy-pilot-new/analysis
```

Use a fresh output directory for a new study. Add `--resume` to continue an
identical interrupted batch. A dry run of `run_experiments.py` writes the design
without running NetLogo; starting that saved design also requires `--resume`.
Do not change the model, runner, config or network library while resuming.

Raw runs and logs remain in ignored `results/`. `analysis/policy_summary.csv`
contains eight policy summaries for each graph and for the equally weighted
combined sample. Changes are paired by graph/seed against the isolated policy;
SD describes spread across paired outcomes, not a confidence interval. Demand
identity, fee accounting and 180 inactive/equivalent-policy cases are checked.
NetLogo also checks its cash/e-float ledger during every run. Pending exchanges
are retained at the horizon, not artificially settled afterward.

The small pilot completed on November 24, 2026. Its reviewed aggregate tables and
runtime estimates are in [the site report](../docs/results/policy-pilot/index.md).
The existing generic dashboard exporter still rejects imported-network studies;
this report is separate and includes only public synthetic aggregate results.
Generating reports does not commit, push or deploy them.
