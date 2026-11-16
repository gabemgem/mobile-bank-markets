# Pooled structural ERGM pilot

For a density-calibrated extension with shrunken market effects, see the
[market density shrinkage pilot](SHRINKAGE_ERGM.md).

Run from `ABM`, with R packages `ergm`, `ergm.multi`, `network`, `igraph`, `callr`,
and `coda` installed. Prepare the observed mutual-willingness CSV library using
the [network export instructions](NETWORKS.md).

```powershell
Rscript tests/pooled_mutual_ergm_checks.R
Rscript scripts/pooled_mutual_ergm.R
```

The pipeline fits three candidates to all markets with at least two respondents.
Empty and complete markets remain in the pooled sample. Source identifiers, fits,
diagnostic draws, and logs stay under the Git-ignored `local-pooled-ergm/` directory.

## Specification

Markets are separate undirected graphs of mutual stated willingness to trade.
The `ergm.multi::Networks()` representation prevents ties between markets.
There are no attributes, homophily terms, or changing networks during ABM runs.

Each candidate contains `N(~ edges, lm = ~ log(n))`, where `n` is the market's
node count. Its effective edges coefficient is `beta0 + beta_size * log(n)`.
The size slope is estimated, rather than fixed as an offset. The other terms
have one coefficient shared by all markets:

| Candidate | Shared structural terms beyond density |
| --- | --- |
| `density` | None |
| `degree` | `gwdegree(0.5, fixed = TRUE)` |
| `degree_closure` | GW degree plus `gwesp(0.5, fixed = TRUE)` |

This is a joint likelihood, not an average of separate fitted coefficients. There
are no market-specific intercepts or random effects. Markets of the same size
have the same modeled graph distribution. Thus the model can learn overall
structural tendencies while still missing variation between particular markets.
Larger markets contribute more potential dyads to the likelihood; this is not an
equal-weighted average of market-level fit scores.

The dependent candidates start from the fitted pooled density coefficients with
their additional terms set to zero. This avoids unstable structural MPLE starting
values. Improved estimation relative to the separate-market pilot may reflect
both pooling and this initialization choice. No estimator fallback is applied.
Likelihood evaluation is disabled; these runs do not provide an AIC ranking.

## Controls and checkpoints

The [configuration](configs/pooled_mutual_ergm.R) reuses the three structural
specifications from the per-market configuration. Defaults are:

- 60 maximum MCMLE iterations, 65,536 fitting burn-in proposals, a 16,384 proposal
  interval, and adaptive fitting effective-size target 128.
- 200 joint diagnostic draws, with 262,144 burn-in proposals and a 65,536 proposal
  interval. Controls are larger than separate-market controls because a joint
  chain updates many markets.
- A hard ten-minute timeout for each fit and each diagnostic stage, enforced in
  separate R worker processes. Seeds, package versions, source hashes, and config
  are saved in the manifest.

These are pilot settings, not convergence guarantees. To change them, use a new
work directory. Repeating an identical command reuses completed stages, including
recorded failures; it does not silently retry them. For example:

```powershell
Rscript scripts/pooled_mutual_ergm.R --work local-pooled-v2 --config local-pooled-config.R
```

Use `--model density`, `--model degree`, or `--model degree_closure` to select one
candidate, and `--phase fit` or `--phase diagnose` to run one stage. The default
is all three candidates and both stages. Changed input/code/config/package hashes
prevent reuse of an incompatible work directory.

## Outputs and interpretation

`markets.csv` records sample inclusion. Each candidate folder contains:

- `fit_result.rds`, `fit.rds`, `coefficients.csv`, and logs: estimates, warnings,
  initialization, elapsed time, and screening status.
- `mcmc.pdf` and `mcmc_screen.csv`: fitting-chain diagnostics for dependent models.
- `observed.csv`, `diagnostic_draws.csv`, and `envelope.csv`: observed and generated
  graph statistics for every market, including triangles, degree SD, isolates,
  component counts, largest component size, and clustering.
- `aggregate_draws.csv`: total edges, isolates, and triangles per joint draw.
- `diagnostic_result.rds`: diagnostic-stage status, warnings, and elapsed time.

Diagnostic draws are split directly from their current edge lists and block IDs,
avoiding costly copies of the full combined object. Tests compare every resulting
adjacency matrix with `uncombine_network(..., use.subnet.cache=FALSE)`.
Checks enforce original market sizes, market
ordering, and preservation of total edge count after splitting; intermarket ties
would fail those checks. No raw person attributes are needed.

Graph diagnostics are attempted for a saved fit even when its coefficient screen
flags a problem. This makes poor generation visible without approving that fit
for use. `ready_for_review` only means basic numerical checks passed. Inspect
mixing, effective sample sizes, warnings, and simulated structure before choosing
a generator. The absolute coefficient cutoff of 10 is a heuristic, not a universal
validity rule.

The 2.5%–97.5% envelopes describe graph variation conditional on fitted coefficients;
they are not confidence intervals or independent significance tests. All markets
used for fitting receive in-sample diagnostics. Comparing the earlier eight-market
sample is useful for continuity, but it is not held-out validation or an estimate
of population-average improvement. Sharing coefficients trades market-specific
fit for estimability and a common generative family.

These commands do not export a production synthetic library or run ABM experiments.
The per-market generator does not consume pooled fits. A pooled generation stage
should follow selection and validation of a specification.

Reference: [official ergm.multi documentation](https://statnet.r-universe.dev/ergm.multi/doc/manual.html).
