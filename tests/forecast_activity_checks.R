for(h in c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R',
  'shrinkage_mutual_ergm_functions.R','validate_shrinkage_functions.R','activity_ergm_functions.R',
  'forecast_activity_functions.R')) source(file.path('scripts',h))
suppressPackageStartupMessages(library(ergm))
cfg<-dget('experiments/configs/forecast_activity.R')
cfg$activity_burnin<-1024L;cfg$activity_interval<-256L
cfg$closure_effects<-2L;cfg$closure_graphs<-3L
cfg$effect_draws<-2L;cfg$graphs_per_effect<-3L
p<-list(id='test',beta=c(-2,0,.7,.7),alpha=c(-1,0),tau=.8,
  activity=list(scales=cfg$activity_scales,weights=c(.5,.2,.2,.1)))
nets<-activity_graphs(6,5,c(-2,-1,0,0,1,2),p$beta,4,cfg,22)
nets<-c(nets,activity_graphs(8,7,rep(0,8),p$beta,4,cfg,23))
p$count_law<-fit_forecast_count(nets,p,cfg)
stopifnot(p$count_law$training_crps<=p$count_law$raw_training_crps+1e-8)
f<-forecast_count_cdf(6,p,cfg)
stopifnot(all(diff(f)>=-1e-12),min(f)>=0,max(f)<=1+1e-12,abs(tail(f,1)-1)<1e-12)
q<-p;q$tau<-0;q$count_law<-list(shift=0,slope=0,scale=1,center=0)
stopifnot(max(abs(forecast_count_cdf(6,q,cfg)-pbinom(0:15,15,plogis(-1))))<1e-10)
p$closure<-fit_forecast_closure(nets,p,cfg,24)
stopifnot(abs(sum(p$closure$weights)-1)<1e-8,all(p$closure$weights>=0),
  p$closure$objective<=p$closure$raw_objective+1e-8,
  all(p$closure$feature_scores[c('degree_sd','max_degree')]<=
    (1+cfg$closure_hub_tolerance)*p$closure$raw_feature_scores[c('degree_sd','max_degree')]+1e-8))
specs<-data.frame(network_id='test',n_nodes=6,n_links=5)
d<-predict_forecast_activity(specs,list(p),'new_density_activity',cfg,25)
j<-predict_forecast_activity(specs,list(p),'new_density_closure',cfg,25)
stopifnot(identical(d$n_links,j$n_links),identical(d$activity_sd,j$activity_sd))
specs$n_links<-14;specs$clustering<-1000
j2<-predict_forecast_activity(specs,list(p),'new_density_closure',cfg,25)
stopifnot(identical(j,j2),all(predict_forecast_activity(specs,list(p),
  'fixed_count_closure',cfg,25)$n_links==14))
q<-p;q$count_law<-list(shift=0,slope=0,scale=1,center=0)
q$closure<-list(scales=1,weights=1)
a<-predict_activity(specs,list(q),'new_market_activity',cfg,26)
b<-predict_forecast_activity(specs,list(q),'new_density_closure',cfg,26)
metrics<-names(activity_statistics(nets[[1]]))
stopifnot(identical(a[metrics],b[metrics]))
cat('PASS: count CDF and calibration, closure regularization/hub guard, paired counts/activity, no count/topology leakage, identity-law nesting.\n')
