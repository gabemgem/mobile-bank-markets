local({
  cfg <- dget('experiments/configs/validate_shrinkage.R')
  cfg$revised <- TRUE
  cfg$structural_terms <- 'gwdegree(0.5, fixed = TRUE) + gwdegree(2, fixed = TRUE) + gwesp(0.5, fixed = TRUE)'
  cfg$regimes <- c('pooled_baseline','calibrated_plugin','calibrated_uncertain',
                   'new_market_uncertain','new_market_raw')
  cfg$calibration_seed <- 301001L
  cfg$calibration_graphs <- 24L
  cfg$calibration_grid <- 25L
  cfg$calibration_shift_bound <- 1.5
  cfg$calibration_scale_bound <- 1.25
  cfg$calibration_quadrature <- 31L
  cfg
})
