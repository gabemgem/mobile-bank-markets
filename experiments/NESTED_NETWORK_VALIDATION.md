# Nested comparison of synthetic-network generators

This comparison concerns **new markets whose kiosk count is supplied**. The
generators predict both the number and arrangement of undirected mutual stated
willingness-to-trade ties, retaining isolated kiosks. It does not validate actual
liquidity trades or the ABM's economic behavior. A prescribed-size-and-density
scenario is a different conditioning problem.

## Frozen candidates and splits

- **Pooled:** size-dependent edge propensity, GWdegree(.5), and GWESP(.5), with
  common coefficients across separate market blocks.
- **Corrected hub:** the [corrected latent-activity generator](FORECAST_ACTIVITY.md),
  including density shrinkage, activity mixture, predictive count calibration,
  and regularized closure mixture with the training hub safeguard.

Candidate definitions and calibration penalties are fixed before this run.
Three size-balanced outer folds hold out each of 100 markets once. Each outer
training partition receives its own two size-balanced inner folds. The outer
test markets enter neither inner fitting, normalization, selection, nor any
outer training bootstrap. Only their kiosk counts enter prediction.

Every fit starts from its partition's own data: no earlier full-data, pilot, or
other-fold fitted coefficient initializes it. The corrected hub model uses the
current training partition's pooled fit to initialize its density-adjusted shared
coefficients, then refits all activity/count/closure calibrations there.

Inner validation compares point-estimated candidates using 12 independent
effect/chain groups of four graphs: 48 graphs per market and candidate. Outer
evaluation uses three matched market-bootstrap training samples for **both**
families, each with 12 groups of four graphs: 144 graphs per market and family.
The same bootstrap source markets are used for the two families, and every stage
of each generator is refitted inside every bootstrap. Three parameter draws are
a bounded uncertainty budget, not a precise estimate of parameter tails.

The assessed procedure is therefore: select a family using inner point-fit CV,
then fit a bootstrap ensemble on the full outer training partition and predict
its untouched outer test partition. Both candidate ensembles are evaluated, as
is the generator selected independently in each outer fold.

## Selection and recommendation rules

The composite score equally weights six marginal predictive scores:

1. Tie count.
2. Degree standard deviation.
3. Maximum degree (hubs).
4. Isolate count.
5. Largest connected component size.
6. Global transitivity (clustering; undefined values recorded as zero).

Each CRPS is divided by its training-partition feature SD, with floors
`1, .25, 1, 1, 1, .1`, respectively, then averaged over features and markets.
No held-out feature determines a scaling constant. Component count and triangle
count are additional diagnostics, not selection criteria. Including both degree
spread and maximum degree makes hub structure an explicit part of this decision.

For inner selection, calculate the per-market paired difference
`corrected_hub - pooled`. Choose the hub model only if its mean plus one paired
standard error is below zero; otherwise choose the simpler pooled family.
This one-SE preference is a decision heuristic, not a significance test.

The final recommendation favors the hub family only if:

- At least two of the three inner selections choose it.
- Its outer composite improvement exceeds one paired standard error.
- All six outer marginal coverages exceed the earlier 85% pilot floor.
- All planned fits, markets, and graph counts are complete.

Otherwise recommend the pooled family, subject to inspecting any numerical
failures rather than treating an incomplete comparison as a validation success.
Nominal intervals are 95%; the 85% floor is only a development screen. The rule
is deliberately conservative about replacing the simpler ABM generator.

## Fair predictive scoring

Four graphs in an effect group share latent variables or an MCMC chain. Treating
all 144 graphs as independent can bias empirical CRPS comparisons. This run
estimates `E|X-y| - .5 E|X-X'|` using independent groups for within-parameter
pairs. Between parameter strata it uses all cross-stratum pairs, weighting the
finite bootstrap mixture uniformly. Both candidates use identical group counts.
Ordinary empirical CRPS is retained alongside this corrected Monte Carlo score.

Outer paired differences receive a 2,000-resample market bootstrap, stratified by
outer fold. These intervals describe case variation conditional on the fitted
folds. They do not account fully for shared training fits, split choice, or the
entire historical model-development process. Scores, coverage, width, fold
variation, and numerical failures must be read together.

All these markets informed earlier model development. New nested splits control
selection in this run but cannot erase that history. This is **nested internal
validation**, not fresh external confirmation or proof that generated networks
will reproduce the ABM's economic outcomes.
Folds hold out markets, not regions or countries; extrapolation to new regional
contexts and any dependence between nearby markets remain untested.

## Running and timing

From `ABM/`:

```powershell
Rscript tests/nested_network_checks.R
Rscript scripts/validate_nested_networks.R --benchmark yes --work local-nested-benchmark
```

The benchmark performs one complete inner fit/prediction cycle. Resume the same
work directory without `--benchmark yes` if code and settings are unchanged.
The full sequential run is:

```powershell
Rscript scripts/validate_nested_networks.R
Rscript scripts/summarize_nested_networks.R
```

Independent outer folds may run in parallel after preparing the manifest:

```powershell
Rscript scripts/validate_nested_networks.R --prepare yes
# In separate terminals, using the same work directory:
Rscript scripts/validate_nested_networks.R --outer 1
Rscript scripts/validate_nested_networks.R --outer 2
Rscript scripts/validate_nested_networks.R --outer 3
# After all three finish:
Rscript scripts/summarize_nested_networks.R
```

The common split plan is immutable; fold workers write separate directories.
The summarizer assembles the complete outer scores and selections. Fit workers
save intermediate checkpoints and logs. A failed stage stops its fold and remains
recorded; no market or bootstrap sample is silently dropped. Changed code, inputs,
or settings require a new work directory. Do not edit a runner while it is active.

Outputs remain under ignored `local-nested-validation/`. Read `comparison.md`,
`outer_summary.csv`, `inner_selections.csv`, `paired_composites.csv`,
`recommendation.csv`, and the per-fold memberships/resample audits. No production
network library, public website update, or large ABM experiment is generated.
