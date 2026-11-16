local({
  structural <- dget('experiments/configs/mutual_ergm.R')$models
  list(models = structural, min_nodes = 2L,
       fit_seed = 81001L, diagnostic_seed = 82001L,
       fit_timeout = 600, diagnostic_timeout = 600,
       max_iterations = 60L, fit_burnin = 65536L, fit_interval = 16384L,
       effective_size = 128L, diagnostic_draws = 200L,
       burnin = 262144L, interval = 65536L,
       max_abs_coefficient = 10, max_standard_error = 10)
})
