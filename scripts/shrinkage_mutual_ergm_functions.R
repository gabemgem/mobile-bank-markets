# Two-stage empirical-Bayes density calibration, then conditional ERGM MCMLE.
# This is not a joint hierarchical ERGM likelihood or a Bayesian posterior fit.
estimate_density_modes <- function(nets, cfg) {
  data <- data.frame(market = factor(names(nets), levels = names(nets)),
    n_nodes = vapply(nets, network::network.size, numeric(1)),
    n_links = vapply(nets, network::network.edgecount, numeric(1)))
  data$dyads <- choose(data$n_nodes, 2)
  data$log_n <- log(data$n_nodes)
  warnings <- character()
  model <- withCallingHandlers(lme4::glmer(
    cbind(n_links, dyads - n_links) ~ log_n + (1 | market),
    data = data, family = binomial(), nAGQ = cfg$density_quadrature,
    control = lme4::glmerControl(optimizer = 'bobyqa',
      optCtrl = list(maxfun = cfg$market_glmm_evaluations))),
    warning = function(w) {
      warnings <<- unique(c(warnings, conditionMessage(w))); invokeRestart('muffleWarning')
    })
  effects <- lme4::ranef(model, condVar = TRUE)$market
  variance <- as.numeric(attr(effects, 'postVar'))
  fixed <- lme4::fixef(model)
  data$prior_log_odds <- unname(fixed[1] + fixed[2] * data$log_n)
  data$market_effect <- effects[['(Intercept)']]
  data$conditional_sd <- sqrt(variance)
  data$shrunk_density <- plogis(data$prior_log_odds + data$market_effect)
  data$raw_shift <- ifelse(data$n_links > 0 & data$n_links < data$dyads,
    qlogis(data$n_links / data$dyads) - data$prior_log_odds, NA_real_)
  list(model = model, effects = setNames(effects[['(Intercept)']], rownames(effects)),
       table = data,
       conditional_sd = setNames(sqrt(variance), rownames(effects)),
       tau = unname(attr(lme4::VarCorr(model)$market, 'stddev')),
       warnings = warnings, convergence = model@optinfo$conv,
       singular = lme4::isSingular(model))
}

shrinkage_formula <- function(nets, effects, structural_terms = NULL) {
  stopifnot(identical(names(effects), names(nets)), all(is.finite(effects)))
  for (i in seq_along(nets))
    network::set.network.attribute(nets[[i]], 'density_shift', unname(effects[i]))
  combined <- ergm.multi::Networks(nets)
  if(is.null(structural_terms)) structural_terms <- 'gwdegree(0.5, fixed = TRUE) + gwesp(0.5, fixed = TRUE)'
  stats::as.formula(paste('combined ~ N(~ edges, lm = ~ log(n) + offset(density_shift)) + N(~',
                          structural_terms,')'),env=environment())
}

shrinkage_initial <- function(beta, cfg) {
  if(!is.null(cfg$structural_terms) && length(beta)==4L) beta <- append(beta,0,after=3L)
  unname(beta)
}

fit_shared_given_modes <- function(nets, effects, beta, cfg, seed, folder) {
  suppressPackageStartupMessages({library(ergm);library(ergm.multi)})
  f <- shrinkage_formula(nets, effects, cfg$structural_terms)
  beta <- shrinkage_initial(beta,cfg)
  warnings <- character()
  fit <- withCallingHandlers(ergm::ergm(f, eval.loglik = FALSE,
    control = ergm::control.ergm(seed = seed, init = unname(beta), parallel = 1,
      MPLE.check = FALSE, MCMLE.maxit = cfg$max_iterations,
      MCMC.burnin = cfg$fit_burnin, MCMC.interval = cfg$fit_interval,
      MCMC.effectiveSize = cfg$effective_size)),
    warning = function(w) {
      warnings <<- unique(c(warnings, conditionMessage(w))); invokeRestart('muffleWarning')
    })
  saveRDS(fit, file.path(folder, 'fit.rds'))
  beta <- stats::coef(fit)
  se <- sqrt(diag(stats::vcov(fit)))
  write.csv(data.frame(term = names(beta), estimate = unname(beta), standard_error = unname(se)),
            file.path(folder, 'coefficients.csv'), row.names = FALSE)
  issues <- c(if (isTRUE(fit$failure)) 'estimation failure',
    if (any(!is.finite(beta)) || any(abs(beta) > cfg$max_abs_coefficient)) 'nonfinite or extreme coefficient',
    if (any(!is.finite(se)) || any(se > cfg$max_standard_error)) 'nonfinite or extreme standard error',
    if (any(grepl('did not converge|not converged|did not mix|degenera|nonidentif|singular',
                  warnings, ignore.case = TRUE))) 'estimation or identification warning')
  if (!is.null(fit$sample)) {
    with_pdf(file.path(folder, 'mcmc.pdf'), function()
      ergm::mcmc.diagnostics(fit, which = 'plots'))
    ess <- coda::effectiveSize(fit$sample)
    z <- unlist(lapply(coda::geweke.diag(fit$sample), function(chain) chain$z))
    write.csv(data.frame(term = names(ess), ess = unname(ess), geweke_z = unname(z)),
              file.path(folder, 'mcmc_screen.csv'), row.names = FALSE)
  }
  list(status = if (length(issues)) 'problem_fit' else 'ready_for_review',
       reason = paste(issues, collapse = '; '), warnings = warnings, beta = beta)
}
