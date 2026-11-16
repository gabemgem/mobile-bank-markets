for(h in c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R',
  'shrinkage_mutual_ergm_functions.R','validate_shrinkage_functions.R','activity_ergm_functions.R'))
  source(file.path('scripts',h))
suppressPackageStartupMessages(library(ergm))
cfg<-dget('experiments/configs/activity_validation.R')
cfg$activity_burnin<-1024L;cfg$activity_interval<-256L
cfg$activity_training_effects<-2L;cfg$activity_training_graphs<-3L
cfg$effect_draws<-2L;cfg$graphs_per_effect<-3L
beta<-c(-2,0,-1,.5)
a<-c(-2,-1,0,0,1,2)
draws<-activity_graphs(6,5,a,beta,3,cfg,11)
stopifnot(all(vapply(draws,network::network.edgecount,numeric(1))==5))
net<-draws[[1]]
degree<-rowSums(as.matrix(net,matrix.type='adjacency'))
stopifnot(abs(unname(summary(net~nodecov('latent_activity')))-sum(degree*a))<1e-8)
for(m in c(0,15)) stopifnot(all(vapply(activity_graphs(6,m,a,beta,2,cfg,12),
  network::network.edgecount,numeric(1))==m))
nets<-c(draws,activity_graphs(6,8,a,beta,3,cfg,13))
parameter<-list(id='test',beta=beta,alpha=c(-2,0),tau=.5)
parameter$activity<-fit_activity_mixture(nets,parameter,cfg,14)
stopifnot(all(parameter$activity$weights>=0),abs(sum(parameter$activity$weights)-1)<1e-8,
  parameter$activity$objective<=parameter$activity$zero_activity_objective+1e-8)
specs<-data.frame(network_id='test',n_nodes=6,n_links=5)
new<-predict_activity(specs,list(parameter),'new_market_activity',cfg,15)
specs$n_links<-14;specs$max_degree<-1000
new2<-predict_activity(specs,list(parameter),'new_market_activity',cfg,15)
stopifnot(identical(new,new2))
fixed<-predict_activity(specs,list(parameter),'fixed_count_activity',cfg,15)
stopifnot(all(fixed$n_links==14))
truth<-as.data.frame(t(activity_statistics(net)));truth$network_id<-'test'
s<-score_predictions(new,truth,6,c('max_degree','n_links'))
stopifnot(nrow(s)==2,all(s$n_draws==6),all(is.finite(s$crps)))
cat('PASS: exact counts, node activity statistic, boundary graphs, regularized simplex, no count leakage, scoring.\n')
