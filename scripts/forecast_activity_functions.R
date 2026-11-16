# Forecast calibration is separate from conditional topology and uses training only.
forecast_count_cdf <- function(n, parameter, cfg, corrected=TRUE) {
  law<-if(corrected) parameter$count_law else list(shift=0,slope=0,scale=1,center=0)
  z<-qnorm((seq_len(cfg$count_quadrature)-.5)/cfg$count_quadrature)
  eta<-parameter$alpha[1]+parameter$alpha[2]*log(n)+law$shift+law$slope*(log(n)-law$center)
  probability<-plogis(eta+law$scale*parameter$tau*z)
  rowMeans(vapply(probability,function(p) pbinom(0:choose(n,2),choose(n,2),p),numeric(choose(n,2)+1)))
}

fit_forecast_count <- function(nets, parameter, cfg) {
  n<-vapply(nets,network::network.size,numeric(1))
  m<-vapply(nets,network::network.edgecount,numeric(1));center<-mean(log(n))
  sizes<-sort(unique(n))
  actual<-lapply(sizes,function(size) rowMeans(outer(0:choose(size,2),m[n==size],'>=')))
  score<-function(par) {
    p<-parameter;p$count_law<-list(shift=par[1],slope=par[2],scale=par[3],center=center)
    sum(vapply(seq_along(sizes),function(i) {
      f<-forecast_count_cdf(sizes[i],p,cfg)
      sum(n==sizes[i])*sum(f^2-2*f*actual[[i]]+actual[[i]])
    },numeric(1)))/length(n)
  }
  raw<-score(c(0,0,1));normalizer<-max(raw,1)
  objective<-function(par) score(par)/normalizer+
    cfg$count_penalty*(par[1]^2+2*par[2]^2+(par[3]-1)^2)
  starts<-list(c(0,0,1),c(0,0,.5),c(-.3,0,.8))
  fits<-lapply(starts,function(start) optim(start,objective,method='L-BFGS-B',
    lower=c(-cfg$count_shift_bound,-cfg$count_slope_bound,0),
    upper=c(cfg$count_shift_bound,cfg$count_slope_bound,cfg$count_scale_bound)))
  admitted<-vapply(fits,function(f) f$convergence==0 && is.finite(f$value),logical(1))
  if(!any(admitted)) stop('No converged count calibration.')
  fit<-fits[admitted][[which.min(vapply(fits[admitted],`[[`,numeric(1),'value'))]]
  if(fit$value>objective(c(0,0,1))) fit<-list(par=c(0,0,1),value=objective(c(0,0,1)),convergence=0)
  list(shift=fit$par[1],slope=fit$par[2],scale=fit$par[3],center=center,
    training_crps=score(fit$par),raw_training_crps=raw,objective=fit$value,
    optimizer_codes=vapply(fits,`[[`,numeric(1),'convergence'),convergence=fit$convergence)
}

fit_forecast_closure <- function(nets, parameter, cfg, seed) {
  suppressPackageStartupMessages({library(ergm);library(ergm.multi)})
  actual<-as.data.frame(do.call(rbind,lapply(nets,activity_statistics)))
  features<-names(cfg$closure_features)
  scales<-pmax(vapply(actual[features],sd,numeric(1)),
    c(clustering=.1,degree_sd=.25,max_degree=1,triangles=1,largest_component=1)[features])
  k<-length(cfg$closure_scales);anchor<-which(cfg$closure_scales==1)
  stopifnot(length(anchor)==1)
  linear<-matrix(0,length(features),k,dimnames=list(features,NULL))
  quadratic<-array(0,c(length(features),k,k),dimnames=list(features,NULL,NULL))
  warnings<-character()
  for(i in seq_along(nets)) {
    components<-vector('list',k)
    for(j in seq_len(k)) {
      rows<-list();beta<-parameter$beta;beta[4]<-beta[4]*cfg$closure_scales[j]
      for(e in seq_len(cfg$closure_effects)) {
        set.seed(seed+i*100L+e)
        sigma<-sample(parameter$activity$scales,1,prob=parameter$activity$weights)
        activity<-rnorm(actual$n_nodes[i],0,sigma)
        draws<-activity_graphs(actual$n_nodes[i],actual$n_links[i],activity,beta,cfg$closure_graphs,
          cfg,seed+10000L+i*100L+e)
        warnings<-unique(c(warnings,attr(draws,'warnings')))
        rows[[e]]<-as.data.frame(do.call(rbind,lapply(draws,activity_statistics)))
      }
      components[[j]]<-do.call(rbind,rows)
    }
    for(f in seq_along(features)) for(j in seq_len(k)) {
      x<-components[[j]][[features[f]]]
      linear[f,j]<-linear[f,j]+mean(abs(x-actual[[features[f]]][i]))/length(nets)
      for(l in seq_len(k)) quadratic[f,j,l]<-quadratic[f,j,l]+
        mean(abs(outer(x,components[[l]][[features[f]]],'-')))/length(nets)
    }
  }
  reference<-as.numeric(seq_len(k)==anchor)
  feature_score<-function(w) vapply(seq_along(features),function(f)
    sum(w*linear[f,])-.5*sum(outer(w,w)*quadratic[f,,]),numeric(1))
  weights<-cfg$closure_features/scales
  a<-as.vector(weights%*%linear)
  b<-apply(quadratic,c(2,3),function(x) sum(weights*x))
  # Parameterize all nonanchor weights; simplex and anchor regularization are explicit.
  other<-setdiff(seq_len(k),anchor)
  expand<-function(v) {w<-numeric(k);w[other]<-v;w[anchor]<-1-sum(v);w}
  objective<-function(v) {
    w<-expand(v);sum(w*a)-.5*sum(outer(w,w)*b)+cfg$closure_penalty*sum((w-reference)^2)
  }
  gradient<-function(v) {
    w<-expand(v);g<-a-as.vector(b%*%w)+2*cfg$closure_penalty*(w-reference)
    g[other]-g[anchor]
  }
  fit<-constrOptim(rep(.1,k-1),objective,gradient,
    ui=rbind(diag(k-1),rep(-1,k-1)),ci=c(rep(0,k-1),-1),
    control=list(reltol=1e-9,maxit=1000),outer.iterations=100)
  if(fit$convergence!=0) stop('Closure mixture did not converge.')
  candidate<-expand(fit$par);baseline<-feature_score(reference)
  hub<-match(c('degree_sd','max_degree'),features)
  fractions<-seq(0,1,length.out=101)
  proposals<-lapply(fractions,function(t) (1-t)*reference+t*candidate)
  feasible<-vapply(proposals,function(w) all(feature_score(w)[hub]<=
    (1+cfg$closure_hub_tolerance)*baseline[hub]+1e-10),logical(1))
  values<-vapply(proposals,function(w) objective(w[other]),numeric(1));values[!feasible]<-Inf
  selected<-which.min(values);w<-proposals[[selected]]
  stopifnot(all(w>=-1e-8),abs(sum(w)-1)<1e-8,all(feature_score(w)[hub]<=
    (1+cfg$closure_hub_tolerance)*baseline[hub]+1e-10))
  list(weights=w,scales=cfg$closure_scales,blend=fractions[selected],
    objective=values[selected],raw_objective=objective(reference[other]),
    feature_scores=setNames(feature_score(w),features),raw_feature_scores=setNames(baseline,features),
    feature_scales=scales,linear=linear,quadratic=quadratic,convergence=fit$convergence,warnings=warnings)
}

predict_forecast_activity <- function(specs,parameters,regime,cfg,seed) {
  suppressPackageStartupMessages({library(ergm);library(ergm.multi)})
  stopifnot(regime %in% c('new_density_activity','new_density_closure','fixed_count_closure'))
  informed<-regime=='fixed_count_closure';closure<-regime!='new_density_activity'
  if(informed) stopifnot('n_links' %in% names(specs))
  rows<-list();index<-0L;warnings<-character()
  for(p in seq_along(parameters)) for(e in seq_len(cfg$effect_draws)) for(i in seq_len(nrow(specs))) {
    parameter<-parameters[[p]];n<-specs$n_nodes[i]
    base_seed<-seed+p*100000L+e*1000L+i*10L
    set.seed(base_seed)
    component<-sample.int(length(parameter$activity$weights),1,prob=parameter$activity$weights)
    sigma<-parameter$activity$scales[component];activity<-rnorm(n,0,sigma)
    if(informed) counts<-rep(specs$n_links[i],cfg$graphs_per_effect) else {
      law<-parameter$count_law;market<-rnorm(1,0,parameter$tau)*law$scale
      probability<-plogis(parameter$alpha[1]+parameter$alpha[2]*log(n)+law$shift+
        law$slope*(log(n)-law$center)+market)
      counts<-rbinom(cfg$graphs_per_effect,choose(n,2),probability)
    }
    # Draw after counts so density-only and joint corrections use identical counts/activity.
    closure_scale<-if(closure) sample(parameter$closure$scales,1,prob=parameter$closure$weights) else 1
    beta<-parameter$beta;beta[4]<-beta[4]*closure_scale
    graphs<-vector('list',cfg$graphs_per_effect)
    for(m in unique(counts)) {
      positions<-which(counts==m)
      draws<-activity_graphs(n,m,activity,beta,length(positions),cfg,base_seed+10000L+positions[1])
      warnings<-unique(c(warnings,attr(draws,'warnings')));graphs[positions]<-draws
    }
    d<-as.data.frame(do.call(rbind,lapply(graphs,activity_statistics)))
    stopifnot(all(d$n_links==counts))
    d$network_id<-specs$network_id[i];d$parameter_id<-parameter$id
    d$effect_id<-e;d$graph_id<-seq_len(cfg$graphs_per_effect)
    d$activity_component<-component;d$activity_sd<-sigma;d$closure_scale<-closure_scale;d$regime<-regime
    index<-index+1L;rows[[index]]<-d
  }
  result<-do.call(rbind,rows);attr(result,'warnings')<-warnings;result
}
