# Regularized latent activity and conditional topology

This opt-in development candidate generates undirected mutual stated
willingness-to-trade networks. Ties are neither acquaintance ties nor observed
liquidity trades. Isolates remain part of each market. No actor attributes or
homophily terms enter the generator.

## Specification

The generator separates the number of ties from their arrangement:

```
P(graph | n) = P(M | n) * P(graph | n, M)
logit(p) = alpha0 + alpha_size * log(n) + b
b ~ Normal(0, tau^2)
M | p ~ Binomial(choose(n, 2), p)

P(graph | n, M, a) proportional to exp(
  theta_degree * GWdegree(0.5) + theta_closure * GWESP(0.5)
  + sum_j a_j * degree_j
)
```

Both geometrically weighted decays are fixed. The topology sampler uses the
`edges` constraint to preserve M. Its node-covariate coefficient is fixed at one.
Activity values are generated Gaussian latent propensities, centered within the
market; no observed kiosk degree is supplied. Centering changes the energy only
by a constant at fixed M. Larger activity dispersion allows more unequal degrees.
Kiosk labels are exchangeable before the activity draw.

Each market draws an activity scale from `{0, 0.75, 1.5, 2.25}` and then draws its
node activities from that Gaussian. Scale zero retains the shared degree-plus-
closure topology without additional latent heterogeneity. A population mixture
permits both relatively homogeneous markets and markets with stronger hubs.

The shared structural coefficients, density regression, and market-effect
variance come from the successful original training-only bootstrap fits.
Activity mixture weights are newly calibrated on each corresponding training
resample. This deliberately avoids another unstable correlated degree coefficient.
It is a simulation-calibrated conditional generator using existing coefficient
anchors, **not** a newly fitted joint latent-variable ERGM likelihood or an exact
Bayesian posterior. Changing the conditioning can change the best coefficients;
the held-out comparison evaluates the resulting generator directly.

## Regularization and uncertainty

For each training market, component-scale simulations use its known size and tie
count. The calibration minimizes the average marginal CRPS of degree SD, maximum
degree, isolate count, and global clustering, weighted `1, .5, .25, .25`.
Features are divided by their training standard deviations, floored at
`.25, 1, 1, .1`, respectively. The penalties are

```
0.03 * (1 - weight_zero)^2 + 0.003 * sum(nonzero_weights^2)
```

The first shrinks toward no additional activity; the second discourages concentrated
nonzero weights. These fixed development choices are explicit in
[the config](configs/activity_validation.R). They have not been tuned by a nested
validation search. Calibration uses three activity vectors per scale and market,
four graphs per vector, with common random numbers across scales. This is a finite
simulation approximation to a marginal proper-score objective; it does not score
the full joint distribution of features. The exact zero-activity solution is
retained if it improves the penalized training objective.

Six training-market bootstrap draws per fold jointly retain the density and
structural anchors and newly estimated mixture. Held-out generation uses four
activity/effect draws and five graphs per draw: 120 graphs per market and protocol.
Activities persist within each five-graph group. New-market tie counts are drawn
afresh for each graph, conditional on the group's density effect. These nested
draws are not 120 independent validation cases. MCMC uses 8,192 burn-in and 2,048
interval proposals per small market, with empty/full graphs handled exactly.
The pilot does not establish adequate mixing for larger or more extreme graphs.

## Protocols and comparison

- **Fixed count:** supply held-out size and tie count; withhold topology.
  Tie-count error is zero by construction, not a forecast success. Structural
  scores can be compared to the old count-informed protocol, but that protocol
  allowed tie counts to fluctuate, so the conditioning also changed.
- **New market:** supply only size; draw density effect, tie count, activity, and
  topology using training-only parameters. No held-out count or degree is read.
  Direct count generation avoids adding a second ERGM count-variation mechanism.
- **Zero-activity control:** use the same fixed-count generator and bootstrap
  anchors with all mass at activity scale zero. This isolates the structural
  contribution of activity from the change to exact count conditioning.

Both folds cover all 100 markets once, training on 50 at a time, with the original
fold membership and bootstrap resamples verified. Previous held-out results
motivated this candidate: these are reused **development folds**, not fresh
confirmation. Coverage is reported against nominal 95% and the earlier 85% pilot
screening floor. Proper scores, mean errors, interval widths, fold consistency,
numerical completeness, and remaining hub misses all matter.

## Running

From `ABM/`, after completing the original shrinkage validation:

```powershell
Rscript tests/activity_ergm_checks.R
Rscript scripts/validate_activity_ergm.R
Rscript scripts/activity_zero_control.R
Rscript scripts/compare_activity_validation.R
```

The optional small sampler check is `Rscript tests/activity_mixing_pilot.R`;
rerun the comparison afterward to include its diagnostics in the report.
`tests/activity_import_fixture.R` writes an isolated, private NetLogo import
fixture for the existing `GeneratedLibraryChecks.java` check.

The driver verifies original input hashes and checksums the parent parameter draws,
memberships, and resamples. It records source/config/package versions and uses
isolated, timed workers with checkpoints. A failed bootstrap stops the run rather
than quietly reducing uncertainty. To change controls, use a new `--work` folder;
never mix changed code with old checkpoints. The control and comparison scripts
also accept a work directory as their first argument.

All outputs remain under ignored `local-activity-validation/`; original artifacts
are unchanged. Read `comparison.md`, `comparison_summary.csv`,
`fold_comparison.csv`, and `mixture_audit.csv` there after a completed run.
`hub_misses.csv` identifies remaining conditional hub/degree interval misses.
No production network library, public site update, or large ABM sweep is generated.
An eventual released synthetic library needs a separate privacy review, even
though generated node labels are anonymous.
