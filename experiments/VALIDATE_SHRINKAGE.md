# Uncertainty and held-out-market validation

For the multi-scale degree extension and training-only predictive density
recalibration, see the [revised development pilot](REVISED_SHRINKAGE.md).

This pilot tests the [two-stage density-shrinkage model](SHRINKAGE_ERGM.md).
It refits the entire model without each held-out market, rather than reusing the
previous all-market fit or initializer.

Run from `ABM`, with the shrinkage pipeline's R dependencies installed:

```powershell
Rscript tests/validate_shrinkage_checks.R
Rscript scripts/validate_shrinkage.R
```

The [pilot config](configs/validate_shrinkage.R) uses two size-balanced folds,
six cluster-bootstrap refits per fold, four market-effect draws per parameter
draw, and five graph replicates per effect. With 100 input markets this means
16 structural ERGM fits (plus cheap density starting fits), 14 density calibrations,
and 120 generated graphs per held-out market per prediction regime. Four regimes
produce 48,000 diagnostic graphs in total. This is a pilot, not a high-precision
bootstrap or a large ABM experiment.

## What is held out

Fold assignment is reproducible and balances node counts without using ties,
clustering, or other network outcomes. Every market is held out once. Entire
markets, rather than individual edges, are the validation units.

Each fold's initializer, density calibration, shared structural ERGM coefficients,
and bootstrap refits use training markets only. The existing full-data fit is
never read. Resampling is restricted to the training fold, with replacement;
duplicated markets receive distinct temporary IDs. The market-level resampling
preserves each sampled graph's internal dependence while propagating sampling
variation jointly through both estimation stages.

## Prediction regimes

| Regime | Information about held-out market | Parameter/effect uncertainty |
| --- | --- | --- |
| `pooled_baseline` | Size only | Training-only common-density degree-plus-closure point fit; graph variation |
| `calibrated_plugin` | Size and total tie count; topology withheld | Training-only calibration hyperparameters and shared coefficients fixed; conditional effect mode fixed |
| `calibrated_uncertain` | Size and total tie count; topology withheld | Joint bootstrap parameter draws; conditional market-effect draws; graph variation |
| `new_market_uncertain` | Size only | Joint bootstrap parameter draws; new Gaussian market-effect draws; graph variation |

The density-informed regimes are **conditional topology-generation tests**. They
must not be presented as predicting density for a completely new market. The
new-market regime receives no held-out tie counts, adjacency, or structural
features. All prediction graphs start empty, avoiding the use of observed test
topologies as MCMC starting states. True graph statistics are joined for scoring
after generation.

## Uncertainty propagation

Each bootstrap refits the binomial mixed calibration and then the conditional
ERGM. A parameter draw therefore contains the calibration intercept/size slope,
Gaussian market SD, and shared ERGM coefficients from the **same** resampled
training markets. Their dependence is retained. No additional asymptotic
coefficient draw is added on top, which would count some sampling variation twice.

For a new market, draw its effect from `Normal(0, tau_bootstrap^2)`.
For a density-informed market, draw from the one-dimensional conditional density
proportional to its binomial count likelihood times that Gaussian prior. Numerical
integration uses a stabilized 4,097-point grid; the plug-in comparison uses its
conditional mode. These conditional effect distributions are from the binomial
calibration approximation, not a full hierarchical ERGM posterior.

Several graph draws are nested inside each market-effect draw. Outputs retain
parameter, effect, and graph IDs so those sources of variability can be separated.
Zero-variance bootstrap calibrations are retained as legitimate boundary cases.
Numerical/estimation failures are logged, never silently replaced or clipped.

This captures finite-sample variation under market resampling, estimated Gaussian
heterogeneity, conditional market-effect uncertainty, and graph randomness within
the chosen two-stage family. It does not propagate uncertainty in survey errors,
missing roster members, market sizes, model specification, or future domain shifts.
It is neither a fully Bayesian posterior analysis nor an exact joint hierarchical
likelihood procedure. Six bootstrap draws cannot establish stable tail behavior;
use substantially more draws for a production uncertainty assessment.

## Scores and pilot readiness

Scores include mean absolute error, central 95% predictive coverage and interval
width, and empirical CRPS for ties, degree SD, isolates, components, clustering,
and triangles. Lower CRPS is better and penalizes unhelpfully broad predictive
distributions. Metrics are reported separately in their native units. A broad
interval containing the observed graph statistic is not sufficient by itself.

The configuration contains transparent **pilot screening rules**, not universal
scientific acceptance thresholds: 25% relative improvement in tie and largest-
component MAE for density-informed generation, and 85% minimum predictive coverage
for selected structural metrics. Check both folds, failure/replicate counts,
CRPS, remaining structural biases, and the intended ABM application. Passing a
small pilot is permission to investigate an exploratory ensemble, not proof of
policy validity or generalization to new markets.

The two regimes support different readiness conclusions. A generator may be useful
for ensembles calibrated to observed densities while failing to predict new-market
densities or topology. Even conditional success does not validate resulting ABM
policy effects; inspect sensitivity to residual hub/component/clustering errors.

## Outputs, timing, and resume

Everything data-derived stays in the ignored `local-shrinkage-validation/` folder:

- `folds.csv` and membership files: train/test assignments.
- Each fold's `pooled/` and `point/`: training-only fits/calibrations.
- `bootstrap-*/resample.csv`, stage checkpoints, fits, and logs: the full bootstrap
  audit trail, including failures.
- `parameter_draws.rds`: joint parameter tuples used for prediction.
- Per-regime prediction checkpoints and `draws.csv`: graph statistics with nested
  simulation IDs, not a production network library.
- `bootstrap_audit.csv`: accepted/rejected refits, calibration variance, singular
  boundary flags, and failure reasons.
- `scores.csv`: held-out scores and actual versus expected replicate counts.

The manifest records input/code/config hashes and package/R versions. An identical
command resumes completed stages. Recorded failures remain recorded; revise the
configuration and use a new work directory for a different attempt. For example:

```powershell
Rscript scripts/validate_shrinkage.R --config local-validation-config.R --work local-validation-v2
```

Summarize completed predictions and apply the recorded pilot screens:

```powershell
Rscript scripts/summarize_shrinkage_validation.R
```

Supply a different work directory as its first positional argument if needed.
It writes `summary.csv`, `fold_summary.csv`, `variance_decomposition.csv`,
`readiness.csv`, `comparison.md`, and a plot. Variance components describe finite
nested draws and include Monte Carlo noise in their group means; they are not an
exact theoretical allocation of inferential uncertainty.

Keep the fit/prediction logs when timing a larger plan. The pilot's point and
bootstrap fits are sequential and have hard timeouts. More bootstrap replicates
increase both fitting and prediction costs. No public report, production graph
library, or ABM batch is created by these commands.

Method/API references: [lme4 mixed-model fitting](https://lme4.github.io/lme4/reference/glmer.html),
[ergm.multi documentation](https://statnet.r-universe.dev/ergm.multi/doc/manual.html).
