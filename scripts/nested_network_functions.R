# All learned quantities are fitted inside the current training partition.
nested_splits<-function(nets,cfg) {
  outer<-market_folds(nets,cfg$outer_folds,cfg$nested_seed)
  splits<-lapply(seq_len(cfg$outer_folds),function(f) {
    test<-outer$network_id[outer$fold==f];train<-setdiff(names(nets),test)
    inner<-market_folds(nets[train],cfg$inner_folds,cfg$nested_seed+100L*f)
    stopifnot(!length(intersect(train,test)),setequal(inner$network_id,train))
    list(train=train,test=test,inner=inner)
  })
  list(outer=outer,splits=splits)
}

nested_scales<-function(nets,cfg) {
  d<-as.data.frame(do.call(rbind,lapply(nets,activity_statistics)))
  pmax(vapply(d[cfg$metrics],sd,numeric(1)),cfg$scale_floors[cfg$metrics])
}

nested_fit_pair<-function(nets,cfg,seed,folder,id) {
  suppressPackageStartupMessages({library(ergm);library(ergm.multi)})
  checkpoint<-function(label,fun) {
    path<-file.path(folder,paste0(label,'.rds'))
    if(file.exists(path)) return(readRDS(path))
    started<-proc.time()[['elapsed']];value<-fun();saveRDS(value,path)
    cat(label,sprintf('%.1f seconds\n',proc.time()[['elapsed']]-started));flush.console();value
  }
  pooled_folder<-file.path(folder,'pooled');dir.create(pooled_folder,showWarnings=FALSE)
  pooled<-checkpoint('pooled_result',function() pooled_fit(nets,cfg$models[['degree_closure']],
    cfg,seed,pooled_folder))
  if(pooled$status!='ready_for_review') stop('Pooled fit failed: ',pooled$reason)
  baseline_beta<-unname(coef(readRDS(file.path(pooled_folder,'fit.rds'))))
  mode<-checkpoint('density',function() estimate_density_modes(nets,cfg))
  messages<-mode$convergence$lme4$messages
  messages<-messages[!grepl('boundary.*singular',messages,ignore.case=TRUE)]
  if(length(messages) || any(mode$convergence$opt!=0) || !is.finite(mode$tau))
    stop('Density calibration failed.')
  shared_folder<-file.path(folder,'shared');dir.create(shared_folder,showWarnings=FALSE)
  shared<-checkpoint('shared_result',function() fit_shared_given_modes(nets,mode$effects,
    baseline_beta,cfg,seed+1L,shared_folder))
  if(shared$status!='ready_for_review') stop('Hub anchor fit failed: ',shared$reason)
  hub<-list(id=id,beta=unname(shared$beta),alpha=unname(lme4::fixef(mode$model)),tau=mode$tau)
  hub$activity<-checkpoint('activity',function() fit_activity_mixture(nets,hub,cfg,seed+2L))
  hub$count_law<-checkpoint('count',function() fit_forecast_count(nets,hub,cfg))
  hub$closure<-checkpoint('closure',function() fit_forecast_closure(nets,hub,cfg,seed+3L))
  list(pooled=list(id=id,beta=baseline_beta),hub=hub,
    warnings=unique(c(pooled$warnings,shared$warnings,hub$activity$warnings,hub$closure$warnings)))
}

nested_pooled_predict<-function(specs,parameters,cfg,seed) {
  suppressPackageStartupMessages({library(ergm);library(ergm.multi)})
  nets<-lapply(specs$n_nodes,function(n) network::network.initialize(n,directed=FALSE))
  names(nets)<-specs$network_id
  f<-pooled_formula(nets,cfg$models[['degree_closure']]);rows<-list();index<-0L
  for(p in seq_along(parameters)) for(e in seq_len(cfg$effect_draws)) {
    draws<-getFromNamespace('simulate.formula','ergm')(f,coef=parameters[[p]]$beta,
      nsim=cfg$graphs_per_effect,seed=seed+p*1000L+e,
      control=ergm::control.simulate.formula(MCMC.burnin=cfg$prediction_burnin,
        MCMC.interval=cfg$prediction_interval))
    for(g in seq_along(draws)) {
      parts<-split_pooled_draw(draws[[g]],nets)
      d<-as.data.frame(do.call(rbind,lapply(parts,activity_statistics)))
      d$network_id<-names(parts);d$parameter_id<-parameters[[p]]$id
      d$effect_id<-e;d$graph_id<-g;d$regime<-'pooled'
      index<-index+1L;rows[[index]]<-d
    }
  }
  do.call(rbind,rows)
}

nested_hub_predict<-function(specs,parameters,cfg,seed) {
  d<-predict_forecast_activity(specs,parameters,'new_density_closure',cfg,seed)
  d$regime<-'corrected_hub';d
}

# Unbiased Monte Carlo CRPS for the equal-weight finite parameter mixture.
# Within a parameter stratum, pairs must come from different effect/chain groups.
nested_crps<-function(x,y,parameter,effect) {
  stopifnot(all(is.finite(x)),length(x)==length(parameter),length(x)==length(effect))
  distance<-abs(outer(x,x,'-'));ids<-unique(parameter)
  stopifnot(length(unique(as.numeric(table(parameter))))==1)
  for(id in ids) stopifnot(length(unique(as.numeric(table(effect[parameter==id]))))==1)
  cross<-matrix(0,length(ids),length(ids))
  for(p in seq_along(ids)) for(q in seq_along(ids)) {
    a<-which(parameter==ids[p]);b<-which(parameter==ids[q])
    if(p==q) {
      allowed<-outer(effect[a],effect[b],'!=')
      if(!any(allowed)) stop('At least two independent effect groups are required.')
      cross[p,q]<-mean(distance[a,b,drop=FALSE][allowed])
    } else cross[p,q]<-mean(distance[a,b,drop=FALSE])
  }
  mean(abs(x-y))-.5*mean(cross)
}

nested_score<-function(draws,truth,scales,cfg,expected) {
  result<-score_predictions(draws,truth,expected,cfg$metrics)
  result$empirical_crps<-result$crps
  for(i in seq_len(nrow(result))) {
    d<-draws[draws$network_id==result$network_id[i] & draws$regime==result$regime[i],]
    result$crps[i]<-nested_crps(d[[result$metric[i]]],result$observed[i],d$parameter_id,d$effect_id)
  }
  result$scale<-unname(scales[result$metric]);result$scaled_crps<-result$crps/result$scale
  stopifnot(all(result$n_draws==expected));result
}

nested_composite<-function(scores,cfg) {
  d<-scores[scores$metric %in% cfg$selection_metrics,]
  stopifnot(all(table(d$network_id,d$regime)==length(cfg$selection_metrics)))
  aggregate(scaled_crps~network_id+regime,d,mean)
}

nested_select<-function(scores,cfg) {
  composite<-nested_composite(scores,cfg)
  pooled<-composite[composite$regime=='pooled',]
  hub<-composite[composite$regime=='corrected_hub',]
  d<-merge(pooled,hub,by='network_id',suffixes=c('_pooled','_hub'))
  difference<-d$scaled_crps_hub-d$scaled_crps_pooled
  se<-sd(difference)/sqrt(length(difference))
  list(selected=if(mean(difference)+se<0) 'corrected_hub' else 'pooled',
    difference=mean(difference),se=se,n=length(difference),paired=d)
}
