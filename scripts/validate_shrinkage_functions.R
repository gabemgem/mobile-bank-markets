# Held-out markets never enter any training fit or bootstrap sample.
market_folds <- function(nets, folds, seed) {
  n <- vapply(nets, network::network.size, numeric(1))
  order <- order(n, names(nets))
  assignment <- integer(length(nets))
  set.seed(seed)
  # Random assignment within consecutive size-ranked blocks balances known sizes.
  for (start in seq(1, length(order), by = folds)) {
    indices <- order[start:min(start + folds - 1L, length(order))]
    assignment[indices] <- sample(seq_len(folds), length(indices))
  }
  data.frame(network_id = names(nets), n_nodes = unname(n), fold = assignment)
}

conditional_market_effect <- function(n, m, alpha, tau, grid_size = 4097L, uniform = NULL) {
  stopifnot(n >= 2, m >= 0, m <= choose(n, 2), tau >= 0,
            length(alpha) == 2, all(is.finite(c(alpha,tau))))
  if (tau < 1e-8) return(0)
  dyads <- choose(n, 2); eta <- alpha[1] + alpha[2] * log(n)
  bound <- max(12 * tau, abs(eta) + 10)
  score <- function(b) m - dyads * plogis(eta + b) - b / tau^2
  mode <- uniroot(score, c(-bound,bound), tol = 1e-10)$root
  if (is.null(uniform)) return(mode)
  stopifnot(uniform >= 0, uniform <= 1)
  grid <- seq(-bound,bound,length.out=grid_size)
  log_weight <- dbinom(m,dyads,plogis(eta + grid),log=TRUE) + dnorm(grid,0,tau,log=TRUE)
  weight <- exp(log_weight - max(log_weight))
  cdf <- cumsum(weight) / sum(weight)
  grid[which(cdf >= uniform)[1]]
}

prediction_graphs <- function(specs, parameters, regime, cfg, seed) {
  suppressPackageStartupMessages({library(ergm);library(ergm.multi)})
  stopifnot(regime %in% c('pooled_baseline','calibrated_plugin','calibrated_uncertain','new_market_uncertain','new_market_raw'),
    all(c('network_id','n_nodes') %in% names(specs)))
  informed <- regime %in% c('calibrated_plugin','calibrated_uncertain')
  if (informed) stopifnot('n_links' %in% names(specs))
  # Prediction starts from empty graphs constructed only from known node counts.
  nets <- lapply(specs$n_nodes, function(n) network::network.initialize(n,directed=FALSE))
  names(nets) <- specs$network_id
  point <- regime %in% c('pooled_baseline','calibrated_plugin')
  rows <- list(); index <- 0L
  for (p in seq_along(parameters)) {
    parameter <- parameters[[p]]
    effect_count <- if (point) 1L else cfg$effect_draws
    for (e in seq_len(effect_count)) {
      set.seed(seed + p * 100L + e)
      effects <- if (regime == 'pooled_baseline') rep(0,nrow(specs)) else
        if (regime %in% c('new_market_uncertain','new_market_raw')) {
          law <- if(regime=='new_market_uncertain' && !is.null(parameter$new_density))
            parameter$new_density else list(shift=0,scale=1)
          law$shift + law$scale * rnorm(nrow(specs),0,parameter$tau)
        } else
          vapply(seq_len(nrow(specs)),function(i) conditional_market_effect(
            specs$n_nodes[i],specs$n_links[i],parameter$alpha,parameter$tau,
            grid_size=cfg$posterior_grid,uniform=if(point) NULL else runif(1)),numeric(1))
      names(effects) <- names(nets)
      formula <- shrinkage_formula(nets,effects,cfg$structural_terms)
      nsim <- if (point) cfg$bootstrap_replicates * cfg$effect_draws * cfg$graphs_per_effect else cfg$graphs_per_effect
      draws <- getFromNamespace('simulate.formula','ergm')(formula,
        coef=shrinkage_initial(parameter$beta,cfg),nsim=nsim,seed=seed + 10000L + p * 100L + e,
        control=ergm::control.simulate.formula(MCMC.burnin=cfg$prediction_burnin,
                                             MCMC.interval=cfg$prediction_interval))
      for (g in seq_along(draws)) {
        parts <- split_pooled_draw(draws[[g]],nets)
        d <- as.data.frame(do.call(rbind,lapply(parts,pooled_statistics)))
        d$network_id <- names(parts);d$parameter_id <- parameter$id
        d$effect_id <- e;d$graph_id <- g;d$regime <- regime
        index <- index + 1L;rows[[index]] <- d
      }
    }
  }
  do.call(rbind,rows)
}

empirical_crps <- function(draws, observed) {
  draws <- sort(draws);n <- length(draws)
  stopifnot(n > 0,all(is.finite(draws)),is.finite(observed))
  mean(abs(draws-observed)) - sum((2*seq_len(n)-n-1)*draws)/n^2
}

score_predictions <- function(predictions, truth, expected_draws,
  metrics = c('n_links','degree_sd','n_isolates','n_components','largest_component','clustering','triangles')) {
  # The truth is joined only after graph generation, never used as a starting graph.
  keys <- unique(predictions[c('network_id','regime')])
  do.call(rbind,lapply(seq_len(nrow(keys)),function(i) {
    key<-keys[i,];p<-predictions[predictions$network_id==key$network_id & predictions$regime==key$regime,]
    actual<-truth[truth$network_id==key$network_id,];stopifnot(nrow(actual)==1)
    do.call(rbind,lapply(metrics,function(metric) {
      x<-p[[metric]];y<-actual[[metric]];range<-quantile(x,c(.025,.975),names=FALSE)
      data.frame(network_id=key$network_id,regime=key$regime,metric=metric,
        observed=y,mean=mean(x),q025=range[1],q975=range[2],n_draws=length(x),
        expected_draws=expected_draws,absolute_error=abs(mean(x)-y),
        covered=y>=range[1]-1e-8 & y<=range[2]+1e-8,
        width=diff(range),crps=empirical_crps(x,y))
    }))
  }))
}
