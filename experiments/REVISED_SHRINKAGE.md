# Multi-scale degree structure and predictive density recalibration

This development pilot extends the [uncertainty validation pipeline](VALIDATE_SHRINKAGE.md).
It uses the same folds, training-market bootstrap samples, and prediction counts
as the first pilot, while retaining all earlier results for comparison.

```powershell
Rscript tests/revised_shrinkage_checks.R
Rscript scripts/validate_shrinkage.R --config experiments/configs/revised_shrinkage_validation.R --work local-shrinkage-revised
Rscript scripts/compare_revised_validation.R
```

To isolate predictive recalibration while retaining the original successful
degree specification and fit objects:

```powershell
Rscript scripts/validate_density_recalibration.R
Rscript scripts/compare_density_recalibration.R
```

This ablation requires the completed original `local-shrinkage-validation/`
artifacts and identical input data. It writes to `local-density-recalibration/`,
checks training/test separation, and refits the forecast correction inside every
original training bootstrap. It does not refit or overwrite structural models.

## Degree and hub specification

The conditional ERGM uses

```
[beta0 + beta_size * log(n_i) + b_hat_i] * edges
  + theta_low * gwdegree(0.5, fixed = TRUE)
  + theta_tail * gwdegree(2, fixed = TRUE)
  + theta_closure * gwesp(0.5, fixed = TRUE)
```

The low-decay term saturates relatively quickly with degree. The additional
slower-saturating term provides information about degree structure beyond the
first few ties, so low-degree and tail behavior need not share one coefficient.
Both decay values are fixed design choices, not estimates or guarantees of fit.
There are still no actor attributes or homophily terms. Setting `theta_tail` to
zero nests the previous model; tests verify equivalent model energies.

All market effects retain the existing two-stage empirical-Bayes density
calibration. The shared ERGM coefficients are refitted conditional on those modes.
The model remains an approximation to a fully joint hierarchical ERGM.

## New-market density distribution

The old size-only regime drew `b_new ~ Normal(0, tau^2)`, where `tau` came from
the binomial density calibration. That need not reproduce the ERGM's density
distribution: structural dependence also generates variation in tie counts.

The revised size-only generator uses

```
b_new = delta + kappa * tau * Z,   Z ~ Normal(0, 1)
```

For every point fit and every bootstrap refit, `delta` and `kappa` are calibrated
**only from that fit's training markets**. The calibration simulates the fitted
ERGM across all observed training sizes and a grid of possible density offsets.
It records count distributions, then selects a mean shift and scale minimizing
mean training-market count CRPS. It never reads held-out counts or topology.

The [configuration](configs/revised_shrinkage_validation.R) makes the numerical
choices explicit:

- 25 density-offset grid points, covering `±(1.5 + 4*tau)`.
- 24 graph samples per grid cell, simulated in a block-separated joint graph.
- 31 equally weighted normal-quantile nodes for integrating new market effects.
- Shift bounded to `[-1.5, 1.5]`; scale bounded to `[0, 1.25]`, permitting a
  reduction, retention, or modest increase in the original effect variation.
- Candidate grid search followed by bounded optimization from three good starts.
  Only converged optimization results that improve the best finite-grid score are
  used; otherwise the best grid candidate is retained. The old `(0,1)` law is
  included, so the calibration surrogate cannot prefer a worse training score.

CDFs are linearly interpolated across the offset grid. The objective averages
market-level CRPS in tie-count units, rather than weighting by possible dyads.
Calibration burn-in is at least 16 proposals per allowed dyad and the interval
at least two, with the validation controls as lower bounds. Current edge lists
are used to count generated ties; cross-market edges are checked and forbidden.
This calibration is a finite-simulation surrogate, not a likelihood estimator.
Held-out prediction uses fresh actual ERGM simulations, not the surrogate CDFs.

The new shift/scale is refitted inside each training-market bootstrap and stored
jointly with that draw's calibration and ERGM parameters. Calibration Monte Carlo
noise is present, and a small bootstrap does not precisely identify tail behavior.

## Separate conditional and new-market protocols

Density-informed predictions keep the original count-stage conditional
market-effect distribution: they receive held-out size and tie count, with
topology withheld. The predictive correction above applies only to size-only
new-market generation. These are explicitly different forecasting protocols;
the corrected new-market distribution and the old binomial conditional effect
distribution are not claimed to be a single exact Bayesian prior/posterior pair.

The revised pilot adds `new_market_raw`, an ablation using the new degree
specification but the old uncorrected Gaussian effect law. It shares parameter,
effect, and graph seeds with the corrected new-market regime. This helps separate
effects of the structural revision from effects of predictive recalibration.

## Comparison and readiness

The original `local-shrinkage-validation/` outputs remain unchanged. A source and
config snapshot is saved under its `source-v1/` folder because new source hashes
intentionally prevent reuse of old checkpoints with changed code. New outputs are
under ignored `local-shrinkage-revised/`.

Compare held-out MAE, CRPS, coverage, interval width, fold stability, and numerical
failures with the original scores. Inspect degree spread/hubs as well as counts,
components, isolates, and clustering. More predictive coverage without better
scores can merely reflect wider distributions.

This is **development cross-validation**, not fresh confirmatory validation:
the previous held-out diagnostics motivated the new specification. Fitting and
predictive calibration still exclude each test market, but repeated reuse of the
same folds for method development can make apparent improvement optimistic.
Confirm a selected model using fresh validation data or an appropriate nested
selection protocol, more bootstrap draws, and independent simulation seeds before
treating it as production-validated.

A numerical screen pass is not a model-quality certificate. Calibration boundaries,
coefficient uncertainty, small-market information limits, and persistent hub or
community errors remain visible in the local artifacts. No production library or
large ABM experiment is created by the validation commands.

References: [statnet degree-term documentation](https://statnet.r-universe.dev/ergm/doc/ergm-term-crossRef.html),
[ergm.multi specification](https://statnet.r-universe.dev/ergm.multi/doc/manual.html).
