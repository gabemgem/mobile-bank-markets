# Per-market undirected structural models; no actor attributes or dyadic covariates.
list(
  models = c(
    density = "edges",
    degree = "edges + gwdegree(0.5, fixed = TRUE)",
    degree_closure = "edges + gwdegree(0.5, fixed = TRUE) + gwesp(0.5, fixed = TRUE)"
  ),
  min_nodes = 6L,
  fit_seed = 41001L,
  diagnostic_seed = 51001L,
  generation_seed = 61001L,
  timeout_seconds = 180,
  max_iterations = 60L,
  diagnostic_draws = 50L,
  burnin = 16384L,
  interval = 4096L,
  replicates = 10L,
  max_abs_coefficient = 10,
  max_standard_error = 10
)
