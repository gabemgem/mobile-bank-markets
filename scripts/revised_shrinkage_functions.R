# Calibrate the *ERGM-generated* new-market count distribution on training data.
# This is simulation-based predictive calibration, not a new likelihood estimator.
calibrate_new_market <- function(nets, beta, tau, cfg, seed) {
  suppressPackageStartupMessages({library(ergm);library(ergm.multi)})
  sizes<-vapply(nets,network::network.size,numeric(1))
  observed<-vapply(nets,network::network.edgecount,numeric(1))
  unique_sizes<-sort(unique(sizes))
  bound<-cfg$calibration_shift_bound + 4*tau
  offsets<-seq(-bound,bound,length.out=cfg$calibration_grid)
  registry<-expand.grid(n_nodes=unique_sizes,offset=offsets)
  basis<-lapply(registry$n_nodes,function(n) network::network.initialize(n,directed=FALSE))
  names(basis)<-sprintf('kernel-%04d',seq_along(basis))
  effects<-setNames(registry$offset,names(basis))
  f<-shrinkage_formula(basis,effects,cfg$structural_terms)
  combined<-environment(f)$combined
  attribute<-network::get.network.attribute(combined,'.blockID.vattr')
  block<-network::get.vertex.attribute(combined,attribute)
  total_dyads<-sum(choose(registry$n_nodes,2))
  burnin<-max(cfg$prediction_burnin,16*total_dyads)
  interval<-max(cfg$prediction_interval,2*total_dyads)
  draws<-getFromNamespace('simulate.formula','ergm')(f,coef=beta,nsim=cfg$calibration_graphs,
    seed=seed,output='edgelist',control=ergm::control.simulate.formula(
      MCMC.burnin=as.integer(burnin),MCMC.interval=as.integer(interval)))
  counts<-do.call(rbind,lapply(draws,function(edges) {
    edges<-as.matrix(edges)[,1:2,drop=FALSE]
    stopifnot(all(block[edges[,1]]==block[edges[,2]]))
    tabulate(as.integer(block[edges[,1]]),nbins=nrow(registry))
  }))
  curves<-lapply(unique_sizes,function(n) {
    indices<-which(registry$n_nodes==n)
    dyads<-choose(n,2)
    pmf<-t(vapply(indices,function(i) tabulate(counts[,i]+1L,nbins=dyads+1L)/nrow(counts),numeric(dyads+1L)))
    cdf<-t(apply(pmf,1,cumsum))
    y<-observed[sizes==n]
    actual_cdf<-rowMeans(outer(0:dyads,y,'>='))
    list(n=n,cdf=cdf,actual_cdf=actual_cdf,n_markets=length(y))
  })
  z<-qnorm((seq_len(cfg$calibration_quadrature)-.5)/cfg$calibration_quadrature)
  objective<-function(par) {
    effect<-par[1]+par[2]*tau*z
    stopifnot(all(effect>=min(offsets)),all(effect<=max(offsets)))
    index<-findInterval(effect,offsets,all.inside=TRUE)
    w<-(effect-offsets[index])/(offsets[index+1]-offsets[index])
    sum(vapply(curves,function(curve) {
      predicted<-colMeans(curve$cdf[index,,drop=FALSE]*(1-w)+curve$cdf[index+1,,drop=FALSE]*w)
      curve$n_markets*sum(predicted^2-2*predicted*curve$actual_cdf+curve$actual_cdf)
    },numeric(1)))/length(nets)
  }
  starts<-rbind(expand.grid(shift=seq(-cfg$calibration_shift_bound,cfg$calibration_shift_bound,length.out=5),
                           scale=seq(0,cfg$calibration_scale_bound,length.out=5)),
                data.frame(shift=0,scale=1))
  scores<-apply(starts,1,objective)
  candidates<-lapply(order(scores)[1:3],function(i) optim(unlist(starts[i,]),objective,
    method='L-BFGS-B',lower=c(-cfg$calibration_shift_bound,0),
    upper=c(cfg$calibration_shift_bound,cfg$calibration_scale_bound)))
  valid<-which(vapply(candidates,function(x) x$convergence==0 && is.finite(x$value),logical(1)))
  best_index<-which.min(scores)
  best<-list(par=unlist(starts[best_index,]),value=scores[best_index],convergence=0)
  method<-'finite grid'
  if(length(valid)) {
    values<-vapply(candidates[valid],`[[`,numeric(1),'value')
    best_valid<-valid[which.min(values)]
    continuous<-candidates[[best_valid]]
    if(continuous$value<best$value) {best<-continuous;method<-'bounded optimization'}
  }
  raw<-objective(c(0,1))
  if(best$value>raw) best<-list(par=c(0,1),value=raw,convergence=0)
  if(tau<1e-8) best$par[2]<-0
  list(shift=unname(best$par[1]),scale=unname(best$par[2]),training_crps=best$value,
    raw_training_crps=raw,convergence=best$convergence,method=method,
    optimizer_codes=vapply(candidates,`[[`,numeric(1),'convergence'),tau=tau,
    seed=seed,burnin=burnin,interval=interval,registry=registry,
    count_draws=counts,starts=cbind(starts,crps=scores))
}
