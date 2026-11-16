# A factorized count/topology generator with regularized latent node activity.
activity_statistics <- function(net) {
  c(pooled_statistics(net), max_degree=max(rowSums(as.matrix(net,matrix.type='adjacency'))))
}

activity_graphs <- function(n, m, activity, beta, nsim, cfg, seed) {
  stopifnot(n>=2,m>=0,m<=choose(n,2),m==as.integer(m),length(activity)==n,
            length(beta)==4,all(is.finite(c(activity,beta))))
  set.seed(seed)
  net<-network::network.initialize(n,directed=FALSE)
  pairs<-utils::combn(seq_len(n),2)
  if(m>0) {
    chosen<-sample.int(ncol(pairs),m)
    network::add.edges(net,pairs[1,chosen],pairs[2,chosen])
  }
  if(m==0 || m==ncol(pairs)) return(rep(list(net),nsim))
  activity<-activity-mean(activity)
  network::set.vertex.attribute(net,'latent_activity',activity)
  formula<-net ~ gwdegree(0.5,fixed=TRUE) + gwesp(0.5,fixed=TRUE) + offset(nodecov('latent_activity'))
  warnings<-character()
  draws<-withCallingHandlers(suppressMessages(getFromNamespace('simulate.formula','ergm')(
    formula,coef=c(unname(beta[3:4]),1),constraints=~edges,nsim=nsim,seed=seed+1L,
    control=ergm::control.simulate.formula(MCMC.burnin=cfg$activity_burnin,
                                          MCMC.interval=cfg$activity_interval))),
    warning=function(w) {
      warnings<<-unique(c(warnings,conditionMessage(w)));invokeRestart('muffleWarning')
    })
  if(nsim==1L) draws<-list(draws)
  stopifnot(length(draws)==nsim,all(vapply(draws,network::network.edgecount,numeric(1))==m),
            all(vapply(draws,network::network.size,numeric(1))==n))
  attr(draws,'warnings')<-warnings
  draws
}

fit_activity_mixture <- function(nets, parameter, cfg, seed) {
  suppressPackageStartupMessages({library(ergm);library(ergm.multi)})
  observed<-as.data.frame(do.call(rbind,lapply(nets,activity_statistics)))
  features<-names(cfg$activity_features)
  scales<-vapply(observed[features],sd,numeric(1))
  scales<-pmax(scales,c(degree_sd=.25,max_degree=1,n_isolates=1,clustering=.1)[features])
  k<-length(cfg$activity_scales)
  a<-numeric(k);b<-matrix(0,k,k);warnings<-character()
  for(i in seq_along(nets)) {
    n<-observed$n_nodes[i];m<-observed$n_links[i]
    component<-vector('list',k)
    for(j in seq_len(k)) {
      rows<-list()
      for(e in seq_len(cfg$activity_training_effects)) {
        set.seed(seed+i*100L+e)
        activity<-rnorm(n)*cfg$activity_scales[j];activity<-activity-mean(activity)
        draws<-activity_graphs(n,m,activity,parameter$beta,cfg$activity_training_graphs,
                              cfg,seed+10000L+i*100L+e)
        warnings<-unique(c(warnings,attr(draws,'warnings')))
        rows[[e]]<-as.data.frame(do.call(rbind,lapply(draws,activity_statistics)))
      }
      component[[j]]<-do.call(rbind,rows)
    }
    for(feature in features) {
      weight<-cfg$activity_features[[feature]]/scales[[feature]]/length(nets)
      y<-observed[[feature]][i]
      for(j in seq_len(k)) {
        x<-component[[j]][[feature]]
        a[j]<-a[j]+weight*mean(abs(x-y))
        for(l in seq_len(k)) b[j,l]<-b[j,l]+weight*mean(abs(outer(x,component[[l]][[feature]],'-')))
      }
    }
  }
  objective<-function(v) {
    w<-c(1-sum(v),v)
    sum(w*a)-.5*sum(outer(w,w)*b)+cfg$activity_penalty*sum(v)^2+
      cfg$activity_weight_penalty*sum(v^2)
  }
  gradient<-function(v) {
    w<-c(1-sum(v),v);g<-a-as.vector(b%*%w)
    g[-1]-g[1]+2*cfg$activity_penalty*sum(v)+2*cfg$activity_weight_penalty*v
  }
  fit<-constrOptim(rep(.4/(k-1),k-1),objective,gradient,
    ui=rbind(diag(k-1),rep(-1,k-1)),ci=c(rep(0,k-1),-1),
    control=list(reltol=1e-9,maxit=1000),outer.iterations=100)
  if(fit$convergence!=0 || !is.finite(fit$value)) stop('Activity mixture optimizer did not converge.')
  weights<-c(1-sum(fit$par),fit$par)
  if(objective(rep(0,k-1))<=fit$value) weights<-c(1,rep(0,k-1))
  stopifnot(all(weights>=-1e-8),abs(sum(weights)-1)<1e-8)
  list(weights=weights,scales=cfg$activity_scales,objective=objective(weights[-1]),
    zero_activity_objective=objective(rep(0,k-1)),feature_scales=scales,
    score_linear=a,score_quadratic=b,convergence=fit$convergence,warnings=warnings)
}

predict_activity <- function(specs, parameters, regime, cfg, seed) {
  suppressPackageStartupMessages({library(ergm);library(ergm.multi)})
  stopifnot(regime %in% c('fixed_count_activity','new_market_activity'))
  informed<-regime=='fixed_count_activity'
  if(informed) stopifnot('n_links' %in% names(specs))
  rows<-list();index<-0L
  for(p in seq_along(parameters)) {
    parameter<-parameters[[p]]
    for(e in seq_len(cfg$effect_draws)) for(i in seq_len(nrow(specs))) {
      n<-specs$n_nodes[i];dyads<-choose(n,2)
      base_seed<-seed+p*100000L+e*1000L+i*10L
      set.seed(base_seed)
      component<-sample.int(length(parameter$activity$weights),1,prob=parameter$activity$weights)
      sigma<-parameter$activity$scales[component]
      activity<-rnorm(n,0,sigma);activity<-activity-mean(activity)
      if(informed) counts<-rep(specs$n_links[i],cfg$graphs_per_effect) else {
        market<-rnorm(1,0,parameter$tau)
        probability<-plogis(parameter$alpha[1]+parameter$alpha[2]*log(n)+market)
        counts<-rbinom(cfg$graphs_per_effect,dyads,probability)
      }
      graphs<-vector('list',cfg$graphs_per_effect)
      for(m in unique(counts)) {
        positions<-which(counts==m)
        draws<-activity_graphs(n,m,activity,parameter$beta,length(positions),cfg,
                              base_seed+10000L+positions[1])
        graphs[positions]<-draws
      }
      d<-as.data.frame(do.call(rbind,lapply(graphs,activity_statistics)))
      stopifnot(all(d$n_links==counts))
      d$network_id<-specs$network_id[i];d$parameter_id<-parameter$id
      d$effect_id<-e;d$graph_id<-seq_len(cfg$graphs_per_effect)
      d$activity_component<-component;d$activity_sd<-sigma;d$regime<-regime
      index<-index+1L;rows[[index]]<-d
    }
  }
  do.call(rbind,rows)
}
