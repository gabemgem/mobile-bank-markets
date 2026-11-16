local({
  cfg <- dget('experiments/configs/shrinkage_mutual_ergm.R')
  cfg$folds <- 2L
  cfg$bootstrap_replicates <- 6L
  cfg$effect_draws <- 4L
  cfg$graphs_per_effect <- 5L
  cfg$split_seed <- 101001L
  cfg$bootstrap_seed <- 102001L
  cfg$prediction_seed <- 103001L
  cfg$posterior_grid <- 4097L
  cfg$prediction_burnin <- 131072L
  cfg$prediction_interval <- 32768L
  # Pilot screening rules, not universal guarantees of scientific validity.
  cfg$min_relative_improvement <- 0.25
  cfg$min_predictive_coverage <- 0.85
  cfg
})
