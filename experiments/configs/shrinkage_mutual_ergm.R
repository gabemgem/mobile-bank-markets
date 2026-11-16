local({
  cfg <- dget('experiments/configs/pooled_mutual_ergm.R')
  cfg$fit_seed <- 91001L
  cfg$diagnostic_seed <- 92001L
  cfg$density_quadrature <- 9L
  cfg$market_glmm_evaluations <- 100000L
  cfg
})
