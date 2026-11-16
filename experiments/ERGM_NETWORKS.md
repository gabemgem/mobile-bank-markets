# Synthetic mutual-trade networks from structural ERGMs

For joint estimation across markets, see the [pooled structural pilot](POOLED_ERGM.md).
For a regularized latent hub mechanism with separate count and topology generation,
see the [latent-activity development validation](ACTIVITY_ERGM.md).
For training-only corrections to new-market density and closure while retaining
that hub mechanism, see [forecast calibration](FORECAST_ACTIVITY.md).
For training-only model selection and outer held-out comparison of pooled and
corrected hub generators, see [nested validation](NESTED_NETWORK_VALIDATION.md).
It retains tiny and empty markets and shares structural coefficients across them.

This pipeline fits **undirected mutual stated-willingness-to-trade networks**,
one market at a time. It uses the ABM survey exports, rather than the earlier
directed acquaintance-network fits. There are no actor attributes, homophily
effects, or dyadic covariates. Networks remain fixed during each ABM run.

Run commands from the `ABM` directory. R packages `readxl` (survey export),
`network`, `ergm`, `igraph`, `callr`, and `jsonlite` are required:

```r
install.packages(c("readxl", "network", "ergm", "igraph", "callr", "jsonlite"))
```

## 1. Prepare the observed mutual networks

```powershell
Rscript scripts/export_market_networks.R
```

The [network guide](NETWORKS.md) describes the source workbook and cleaning.
Both operators must report willingness for an undirected edge to exist.
Respondents with no mutual ties remain as isolates. Missing reverse reports
create no edge. Reported acquaintance and actual trade are different relationships.
Unobserved roster members are not invented.

Inputs are `data/networks.csv`, `data/nodes.csv`, and `data/edges.csv`. The pipeline
requires their observed-mutual-willingness type label and checks graph integrity.
Survey exports and the working directory `local-ergm/` are Git-ignored. Saved fits,
market identifiers, logs, and the case-to-market crosswalk stay in that directory.

## 2. Fit a small pilot, then the candidate models

The configuration is [configs/mutual_ergm.R](configs/mutual_ergm.R).

| Model ID | Terms | Structural question |
| --- | --- | --- |
| `density` | `edges` | What does density alone explain? |
| `degree` | `edges + gwdegree(0.5, fixed = TRUE)` | Is the degree pattern better represented with a geometrically weighted degree term? |
| `degree_closure` | Degree model plus `gwesp(0.5, fixed = TRUE)` | Does a shared-partner closure term improve the representation? |

The geometrically weighted terms use a fixed decay of 0.5. These are candidate
specifications, not a claim that the richest one fits best. The script restricts
formulas to these structural specifications. Adding another specification means
extending both the configuration and the allowlist in `scripts/mutual_ergm.R`.
There is no `mutual` term: every input edge is already undirected.

Start with two markets, ordered by source ID, and the density baseline:

```powershell
Rscript scripts/mutual_ergm.R fit --model density --limit 2
Rscript scripts/mutual_ergm.R fit --model degree_closure --limit 2
```

Each case runs in a separate R process with a configurable hard timeout (180
seconds by default), covering fitting and diagnostics together. Inspect
`elapsed_seconds` in `local-ergm/fit_summary.csv` to gauge fitting costs. Complex
cases may take longer than the pilot. A full pass fits all three models:

```powershell
Rscript scripts/mutual_ergm.R fit
```

Fits use MCMLE where needed; there is no automatic estimator or model fallback.
Networks below six nodes, empty graphs, and complete graphs are explicitly
skipped. These cases have insufficient information for this fitting workflow;
their omission can affect representativeness. They are not replaced with random
graphs. Failed fits and failed diagnostics are also recorded separately.

Rerunning the same command skips saved cases. Use `--retry true` to retry failed,
problematic, or skipped cases; completed cases are retained. Input hashes, config,
code, R version, and package versions are checked before reuse. When any change,
choose a new work directory, for example `--work local-ergm-v2`. An interrupted
case without a completed checkpoint is rerun. Keep using the same `--work` and
`--config` values in generation commands.

## 3. Review diagnostics and choose a specification

`fit_summary.csv` lists every market/model combination, including those not run.
Each case folder contains:

- `coefficients.csv` and `fit.rds`: fitted parameters and the local R fit object.
- `mcmc.pdf`: trace and autocorrelation diagnostics for dependent models; the
  density-only model has no MCMC diagnostic plot.
- `gof.pdf`, `gof.txt`, and `gof.rds`: simulated goodness of fit for degree,
  edgewise shared partners, distances, and model statistics.
- `envelope.csv`: observed values and simulated mean/2.5%/97.5% quantiles for
  density, degree variation, isolates, components, and clustering.
- `diagnostic_draws.csv`, worker logs, and `result.rds`: diagnostic draws,
  messages, status, warnings, and elapsed time.

`ready_for_review` means the numerical checks and diagnostics completed. It does
**not** certify convergence, mixing, or substantive fit. Review warnings and MCMC
plots, then compare observed graph statistics with the simulated distributions.
GOF envelopes are descriptive simulation ranges, not confidence intervals.
Clustering is recorded as zero for graphs with no connected triples; node count
is fixed. The default 50 diagnostic draws are a starting point. Check stability
with longer chains and more draws before adopting a generator.

Large/nonfinite coefficients or standard errors, fitting failures, and recognized
convergence/mixing warnings prevent generation. Numerical cutoffs are configurable
screening rules. No automated p-value or AIC rule selects a model. The generation
command uses your explicit model choice for every usable market; inspect the
coverage/exclusions rather than choosing a specification solely for its coverage.

## 4. Generate an ensemble from the chosen model

For example, after reviewing the degree-and-closure fits:

```powershell
Rscript scripts/mutual_ergm.R generate --model degree_closure
```

Only `ready_for_review` cases for that model are used. Other cases are excluded
and counted; there is no substitution with a simpler model. Generation saves
`generation_selection.csv` locally to document all case statuses. `--limit 2`
can restrict generation to the same pilot markets.

The default is ten graph draws per eligible market, with separate reproducible
generation seeds. Each chain uses 16,384 burn-in proposals and an interval of
4,096. These are starting controls, not guarantees of mixing. Each generated
graph has the source market's node count; edge count, isolates, and connectivity
are allowed to vary. Empty or disconnected draws are retained as model outcomes.
Fits are held fixed: the ensemble represents graph variation conditional on
estimated coefficients, not parameter uncertainty. Small-market fit exclusions
and equal replicates per retained market define the ensemble's weighting.

The command writes `synthetic-networks/networks.csv`, `nodes.csv`, `edges.csv`, and
`provenance.R`. The catalog records anonymous fit IDs, model formulas, fit and
generation seeds, chain controls, package version, and realized graph statistics.
All vertices, including isolates, are exported. The provenance file records input
and code hashes and the configuration; original market/person IDs and fitted
objects are not exported. New IDs do not constitute a privacy guarantee for
survey-derived networks. Files remain available for your repository review.

Existing nonempty libraries are never overwritten. Use `--out local-ergm/library-v2`
for another staging library, then copy the reviewed library files into
`synthetic-networks/` when replacing the active library. NetLogo reads only that
active location. Generation assembles a complete library before installing it.

## 5. Use the graphs in the ABM

In desktop NetLogo, choose **Imported synthetic**, click **Choose local network**,
select a graph, and click **Setup**. The loaded type explicitly identifies an
ERGM-generated undirected mutual stated-willingness network.

Generation also writes `local-ergm/synthetic_study.json`: a grid crossing every
generated graph with three sharing policies, settlement delays 0–2, and five ABM
seeds, for 500 ticks per run. That is **45 runs per graph**, plus two discarded
warm-ups per batch. Other controls use model defaults, which the experiment
harness resolves into the saved design. Edit the generated study to set explicit
baselines, reduce its size, or create OAT/LHS variants. Do not sweep kiosk count
or density for imported graphs; those controls do not alter the library.

```powershell
python experiments/run_experiments.py local-ergm/synthetic_study.json --out results/ergm-study --dry-run --resume
```

Inspect `design.csv` and the run count before running. Benchmark the engine with
the [experiment guide](RUNNING.md); its built-in random workloads give approximate
guidance for imported graphs. For a direct timing pilot, copy the generated config,
keep one graph and a few seeds, reduce ticks, and time that separate small run.
Do not launch the full ensemble just to estimate its cost. Once ready:

```powershell
python experiments/run_experiments.py local-ergm/synthetic_study.json --out results/ergm-study --resume
```

Keep graph replicates distinct from ABM seeds in analysis. Each graph is a network
draw, and each ABM seed is a stochastic run conditional on that graph. Treating all
runs as independent market observations would exaggerate precision. Node count
and total market demand also affect demand per kiosk.

The public dashboard exporter currently accepts only built-in Synthetic random
studies. Imported ERGM studies produce the full local harness outputs; dashboard
support requires a separate exporter extension.

## Pipeline checks

```powershell
Rscript tests/mutual_ergm_checks.R
```

These checks use small handcrafted graphs, not survey records. They exercise
isolate preservation, exclusions, density and structural fits, diagnostics,
checkpoint reuse, reproducible library generation, and ABM configuration output.

The implementation uses statnet's fitted-model simulation and GOF interfaces;
see the [official ERGM tutorial](https://statnet.org/workshop-ergm/ergm_tutorial.html).
