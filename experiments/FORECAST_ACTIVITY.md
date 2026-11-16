# New-market density and closure calibration with retained hubs

This opt-in extension of [latent activity](ACTIVITY_ERGM.md) generates undirected
mutual stated willingness-to-trade networks, retaining isolates. These are
structural synthetic networks, not observed liquidity transactions.

## What stays fixed

Each original training bootstrap retains its shared GWdegree coefficient, latent
Gaussian activity scales, and regularized activity mixture weights. No observed
held-out degree, actor attribute, or homophily enters prediction. Existing fit
objects are read without modification. New training calibrations and predictions
write to a separate ignored directory.

## Count distribution

The previous count stage draws a binomial-logistic-normal count from size. The
correction is

```
logit(p) = alpha0 + alpha_size * log(n)
           + delta0 + delta_size * (log(n) - training_center)
           + kappa * b
b ~ Normal(0, tau^2)
M | p ~ Binomial(choose(n, 2), p)
```

The three correction parameters minimize training-market average count CRPS.
The count CDF is computed using 61 midpoint normal-quantile quadrature nodes and
binomial CDFs; no graph simulations enter this calibration. Markets have equal
weight, rather than weighting by the number of dyads. The objective divides CRPS
by `max(original training CRPS, 1)` and adds

```
0.01 * (delta0^2 + 2 * delta_size^2 + (kappa - 1)^2)
```

Bounds are `delta0 ∈ [-1.5, 1.5]`, `delta_size ∈ [-1, 1]`, and `kappa ∈ [0, 1.5]`.
Three starts are attempted; only converged solutions are eligible. The unchanged
law `(0, 0, 1)` is retained if its penalized score is better. The training center
and all corrections are learned anew inside each training-market bootstrap.
This is predictive calibration, not a new hierarchical likelihood fit.

## Closure distribution

The fixed-count ERGM remains

```
theta_degree * GWdegree(0.5) + q * theta_closure * GWESP(0.5)
  + sum_j activity_j * degree_j
```

Each market/effect group draws `q` from a population mixture over `{0, .5, 1, 1.5}`.
The value one is the unchanged closure model; zero removes the explicit closure
term while retaining activity-induced clustering. Both geometric decays stay fixed.
Closure and activity are independent population draws in this candidate; their
dependence on each other or density is not estimated.

Training simulations receive training size and tie count. Three activity draws
and four graphs per scale/market use matched random numbers across closure scales.
The mixture minimizes marginal CRPS for clustering, degree SD, maximum degree,
triangles, and largest component, with weights `1, 1, .5, .25, .25`. Features are
divided by training SD with floors `.1, .25, 1, 1, 1`. The penalty is
`.02 * sum((weights - unchanged_closure_weights)^2)`.
Clustering means global transitivity; it is recorded as zero when the graph has
no connected triples and transitivity is undefined.

A further safeguard blends the selected mixture back toward unchanged closure on
a 101-point grid until neither training degree-SD nor maximum-degree CRPS worsens
by more than 2% relative to the unchanged closure kernel. The best feasible
penalized score is selected, including unchanged closure. This is a finite
simulation calibration with a training safeguard, not a guarantee about held-out
hubs or the global optimum. Held-out hub retention is assessed separately.

## Held-out experiment

The same two size-balanced folds hold out each of 100 markets once. Each fold has
six original market bootstrap resamples. The new corrections are estimated using
only those resamples, preserving their joint association with density, structural,
and activity parameters. No full-data fit initializes the corrections.

Three protocols use 120 graphs per held-out market each:

- `new_density_activity`: corrected counts, unchanged activity/closure topology.
- `new_density_closure`: corrected counts and the closure mixture, retained activity.
- `fixed_count_closure`: supplied held-out size/count, new closure mixture and
  retained activity; topology is withheld. Zero count error is by construction.

The two new-market protocols share exact count and activity draws, isolating the
closure correction. All prediction parameters come from training. Each bootstrap
has four effect/activity groups of five graph draws; nested graphs are not
independent validation cases. Count laws also receive quadrature-based scores for
both previous and corrected distributions, reducing finite graph-simulation noise.
These count scores use the six-bootstrap mixture; the pooled ERGM comparator has
only its existing finite-simulation scores.
The quadrature check refines final old/new count scores to 241 nodes without
refitting their 61-node calibrations, and records the numerical difference.

Compare CRPS (lower is better), mean errors, central 95% coverage and width, fold
consistency, numerical completeness, and conditional hub retention. The earlier
new-market screen requires at least 85% coverage on selected metrics and count,
component, and clustering CRPS no worse than the pooled baseline. We also report
whether fixed-count degree/hub CRPS stays within 2% of the previous activity model
with coverage above the pilot floor. These are development screens, not statistical
noninferiority tests or scientific certification.

Previous held-out diagnostics motivated this extension. Reusing these folds for
development makes this comparison unsuitable as fresh confirmatory validation.
Finite calibration kernels, six bootstraps, marginal feature scores, fixed activity
and coefficient anchors, and simple population mixture assumptions remain limits.

## Commands

From `ABM/`, after the original activity validation has completed:

```powershell
Rscript tests/forecast_activity_checks.R
Rscript scripts/validate_forecast_activity.R
Rscript tests/forecast_count_quadrature.R
Rscript scripts/compare_forecast_activity.R
```

`Rscript tests/forecast_sampler_checks.R` is an optional small chain-length check
for the expanded closure range; rerun the comparison to include its diagnostics.

The driver accepts `--input`, `--parent`, `--config`, and `--work`. It verifies the
parent source and data hashes, memberships, and bootstrap samples. Isolated timed
workers save checkpoints and errors; any failed stage stops rather than dropping
draws. Changed source/config requires a new work directory.

Read `local-forecast-activity/comparison.md`, `calibration_audit.csv`,
`comparison_summary.csv`, `fold_comparison.csv`, and `quadrature_count_scores.csv`.
The optional refinement check also writes `quadrature_refined_scores.csv`;
simulation warnings are retained in `simulation_warnings.csv` and worker logs.
The comparison script accepts an optional work-directory argument.
All data-derived artifacts remain local and ignored. These commands neither
release a network library nor publish results or run a large ABM sweep.
