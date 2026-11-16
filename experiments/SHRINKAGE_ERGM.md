# Market density shrinkage pilot

For uncertainty propagation and held-out tests, see the
[validation pilot](VALIDATE_SHRINKAGE.md).

This pipeline adds empirical-Bayes market density calibration to the pooled
undirected degree-plus-closure ERGM. It uses no actor attributes or homophily.
It is a **two-stage approximation**, not a jointly estimated hierarchical ERGM
or a full Bayesian fit.

Run from `ABM`, after the [pooled pilot](POOLED_ERGM.md) has produced its
degree-plus-closure fit. Add the R package `lme4` to the pooled pipeline's packages.

```powershell
Rscript tests/shrinkage_mutual_ergm_checks.R
Rscript scripts/shrinkage_mutual_ergm.R
```

## Specification

First, fit the observed market tie counts using a binomial mixed model:

```
m_i ~ Binomial(choose(n_i, 2), p_i)
logit(p_i) = a0 + a_size * log(n_i) + b_i
b_i ~ Normal(0, tau^2)
```

The population coefficients and `tau` are estimated with `lme4::glmer`, using
nine-point adaptive quadrature. Market effects are empirical-Bayes conditional
modes. Gaussian shrinkage keeps empty and complete markets finite and draws
information-poor markets toward the population size relationship. These count
likelihoods treat dyads as independent **only for density calibration**; they are
not the likelihood of the structural ERGM. Consequently, this stage is an
approximation when edges are dependent.

Next, hold the estimated market effects fixed and refit the shared structural
coefficients by conditional MCMC maximum likelihood:

```
log Pr(Y_i = y | b_hat_i) =
  [beta0 + beta_size * log(n_i) + b_hat_i] * edges(y)
  + theta_degree * gwdegree(y; decay=0.5)
  + theta_closure * gwesp(y; decay=0.5)
  - log Z_i
```

The refitted `beta` values need not equal the density GLMM's `a` values. Structural
dependence affects the ERGM's marginal density. The calibration table's
`shrunk_density` is the binomial-stage estimate, not a substitute for the generated
ERGM density in `envelope.csv`.

All 100 markets remain separate blocks. Offsets use
`N(~edges, lm=~log(n)+offset(density_shift))`; their coefficient is fixed at one,
not re-estimated as a free predictor. The degree and closure coefficients remain
shared. The existing pooled fit supplies starting values; it is not overwritten.

This pilot uses density-based calibration because an exploratory conditional-logit
random-intercept fit with ERGM change statistics estimated zero variance. That
approximation did not address the observed generative density mismatch. Neither
the exploratory boundary result nor the two-stage fit establishes a fully joint
hierarchical estimate of market variance.

## Configuration, files, and resuming

[configs/shrinkage_mutual_ergm.R](configs/shrinkage_mutual_ergm.R) inherits the
pooled simulation and MCMLE controls and sets separate seeds and GLMM controls.
Defaults retain all markets and generate 200 joint diagnostic draws. Computation
is isolated in R workers with hard timeouts. Existing completed stages are reused;
changing source, data, config, package versions, or baseline hashes requires a new
work directory.

```powershell
Rscript scripts/shrinkage_mutual_ergm.R --work local-shrinkage-v2 --config local-shrinkage-config.R
```

Other options are `--input`, `--baseline`, and `--help`. The default output folder
`local-shrinkage-ergm/` is Git-ignored. It contains:

- `density_modes.rds`: mixed model, variance, market modes, conditional SDs, and
  optimizer diagnostics.
- `market_effects.csv`: observed counts, population log odds, market effects,
  binomial shrinkage estimates, and raw interior-market deviations for comparison.
  Raw shifts are missing for empty/complete markets; the fitted effects remain finite.
- `fit.rds`, `coefficients.csv`, MCMC checks, stage results, logs, and manifest.
- The same observed/draw/envelope/aggregate diagnostic CSVs as the pooled pilot.

All market identifiers and data-derived outputs remain local. This command neither
exports a production graph library nor publishes dashboard results.

## Interpretation limits

The pilot compares **conditional reproduction of existing markets** using their
own observed tie counts to estimate their offsets. Improvement is expected and
must not be described as held-out prediction. To assess new-market generation,
validate a procedure for drawing new market effects, preferably with held-out
markets and refitting of both stages.

Diagnostic draws hold estimated effects and shared coefficients fixed. They omit
uncertainty in effects, `tau`, calibration parameters, and ERGM coefficients.
Conditional SDs in the calibration table come from the binomial approximation;
they are not full hierarchical-ERGM posterior SDs. Conditional ERGM standard
errors also do not include first-stage estimation uncertainty. No AIC comparison
between the two-stage model and ordinary pooled fits is supplied.

Check density, isolates, component sizes, hubs, and clustering together. Better
edge counts alone do not establish a suitable generator for liquidity-sharing
experiments. Compare simulation means as well as ranges so wider variation does
not masquerade as improved accuracy.

References: [lme4 GLMM fitting](https://lme4.github.io/lme4/reference/glmer.html),
[ergm.multi network offsets](https://statnet.r-universe.dev/ergm.multi/doc/manual.html).
