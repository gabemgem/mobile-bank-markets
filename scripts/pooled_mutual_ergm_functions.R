# Pooled structural models: distinct markets, shared coefficients, size-dependent density.
pooled_formula <- function(nets, terms) {
  combined <- ergm.multi::Networks(nets)
  rest <- sub('^edges( \\+ )?', '', terms)
  rhs <- 'N(~ edges, lm = ~ log(n))'
  if (nzchar(rest)) rhs <- paste(rhs, '+ N(~', rest, ')')
  stats::as.formula(paste('combined ~', rhs), env = environment())
}

pooled_fit <- function(nets, terms, cfg, seed, folder) {
  suppressPackageStartupMessages({library(ergm); library(ergm.multi)})
  warnings <- character()
  capture <- function(expr) withCallingHandlers(expr, warning = function(w) {
    warnings <<- unique(c(warnings, conditionMessage(w))); invokeRestart('muffleWarning')
  })
  formula <- pooled_formula(nets, terms)
  initial <- NULL
  if (terms != 'edges') {
    # Start all dependent candidates from the same fitted density model.
    baseline <- capture(ergm::ergm(pooled_formula(nets, 'edges'), eval.loglik = FALSE,
      control = ergm::control.ergm(seed = seed, MPLE.check = FALSE, parallel = 1)))
    initial <- c(unname(stats::coef(baseline)), rep(0, if (grepl('gwesp', terms)) 2 else 1))
  }
  fit <- capture(ergm::ergm(formula, eval.loglik = FALSE,
    control = ergm::control.ergm(seed = seed, init = initial, MPLE.check = FALSE,
      parallel = 1, MCMLE.maxit = cfg$max_iterations,
      MCMC.burnin = cfg$fit_burnin, MCMC.interval = cfg$fit_interval,
      MCMC.effectiveSize = cfg$effective_size)))
  saveRDS(fit, file.path(folder, 'fit.rds'))
  beta <- stats::coef(fit)
  se <- capture(sqrt(diag(stats::vcov(fit))))
  write.csv(data.frame(term = names(beta), estimate = unname(beta), standard_error = unname(se)),
            file.path(folder, 'coefficients.csv'), row.names = FALSE)
  issues <- c(if (isTRUE(fit$failure)) 'estimation failure',
    if (any(!is.finite(beta)) || any(abs(beta) > cfg$max_abs_coefficient)) 'nonfinite or extreme coefficient',
    if (any(!is.finite(se)) || any(se > cfg$max_standard_error)) 'nonfinite or extreme standard error',
    if (any(grepl('did not converge|not converged|did not mix|degenera|nonidentif|singular',
                  warnings, ignore.case = TRUE))) 'estimation or identification warning')
  if (!is.null(fit$sample)) {
    with_pdf(file.path(folder, 'mcmc.pdf'), function()
      capture(ergm::mcmc.diagnostics(fit, which = 'plots')))
    ess <- coda::effectiveSize(fit$sample)
    z <- coda::geweke.diag(fit$sample)
    z <- as.numeric(unlist(lapply(z, function(chain) chain$z)))
    write.csv(data.frame(term = names(ess), ess = unname(ess), geweke_z = z),
              file.path(folder, 'mcmc_screen.csv'), row.names = FALSE)
  }
  list(status = if (length(issues)) 'problem_fit' else 'ready_for_review',
       reason = paste(issues, collapse = '; '), warnings = warnings, initial = initial)
}

pooled_statistics <- function(net) {
  a <- as.matrix(net, matrix.type = 'adjacency')
  c(graph_statistics(net), triangles = sum(diag(a %*% a %*% a)) / 6)
}

split_pooled_draw <- function(draw, nets) {
  # Extract current edges directly; avoid repeatedly copying the large block object.
  attribute <- network::get.network.attribute(draw, '.blockID.vattr')
  block <- network::get.vertex.attribute(draw, attribute)
  groups <- unique(block)
  edges <- as.matrix(network::as.edgelist(draw))[, 1:2, drop = FALSE]
  stopifnot(length(groups) == length(nets), all(block[edges[,1]] == block[edges[,2]]))
  parts <- lapply(seq_along(nets), function(i) {
    vertices <- which(block == groups[i])
    part <- network::network.initialize(length(vertices), directed = FALSE)
    local <- edges[block[edges[,1]] == groups[i], , drop = FALSE]
    if (nrow(local)) network::add.edges(part, match(local[,1], vertices), match(local[,2], vertices))
    part
  })
  names(parts) <- names(nets)
  stopifnot(identical(vapply(parts, network::network.size, numeric(1)),
                     vapply(nets, network::network.size, numeric(1))),
    sum(vapply(parts, network::network.edgecount, numeric(1))) == network::network.edgecount(draw))
  parts
}

pooled_diagnostics <- function(fit_path, nets, cfg, seed, folder) {
  suppressPackageStartupMessages({library(ergm); library(ergm.multi)})
  fit <- readRDS(fit_path)
  warnings <- character()
  draws <- withCallingHandlers(stats::simulate(fit, nsim = cfg$diagnostic_draws, seed = seed,
    control = ergm::control.simulate.ergm(MCMC.burnin = cfg$burnin,
      MCMC.interval = cfg$interval)), warning = function(w) {
        warnings <<- unique(c(warnings, conditionMessage(w))); invokeRestart('muffleWarning')
      })
  observed <- as.data.frame(do.call(rbind, lapply(nets, pooled_statistics)))
  observed$network_id <- names(nets)
  simulated <- do.call(rbind, lapply(seq_along(draws), function(i) {
    parts <- split_pooled_draw(draws[[i]], nets)
    d <- as.data.frame(do.call(rbind, lapply(parts, pooled_statistics)))
    d$network_id <- names(parts); d$draw <- i; d
  }))
  rows <- lapply(names(nets), function(id) {
    actual <- observed[observed$network_id == id, ]
    sample <- simulated[simulated$network_id == id, ]
    metrics <- setdiff(names(observed), 'network_id')
    data.frame(network_id = id, metric = metrics, observed = unname(unlist(actual[1, metrics])),
      mean = vapply(sample[metrics], mean, numeric(1)),
      q025 = vapply(sample[metrics], quantile, numeric(1), probs = .025),
      q975 = vapply(sample[metrics], quantile, numeric(1), probs = .975))
  })
  envelope <- do.call(rbind, rows)
  envelope$outside <- envelope$observed < envelope$q025 - 1e-8 |
                      envelope$observed > envelope$q975 + 1e-8
  write.csv(observed, file.path(folder, 'observed.csv'), row.names = FALSE)
  write.csv(simulated, file.path(folder, 'diagnostic_draws.csv'), row.names = FALSE)
  write.csv(envelope, file.path(folder, 'envelope.csv'), row.names = FALSE)
  totals <- aggregate(simulated[c('n_links','n_isolates','triangles')],
                      list(draw = simulated$draw), sum)
  write.csv(totals, file.path(folder, 'aggregate_draws.csv'), row.names = FALSE)
  list(status = 'complete', warnings = warnings, n_markets = length(nets),
       n_draws = length(draws))
}
