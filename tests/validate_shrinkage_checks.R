suppressPackageStartupMessages({library(ergm);library(ergm.multi)})
for(file in c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R',
             'shrinkage_mutual_ergm_functions.R','validate_shrinkage_functions.R')) source(file.path('scripts',file))
nets<-lapply(c(2,3,4,5,6,7),function(n) network::network.initialize(n,directed=FALSE))
names(nets)<-letters[1:6]
a<-market_folds(nets,2,123);network::add.edges(nets[[6]],1,2)
stopifnot(identical(a,market_folds(nets,2,123)),all(table(a$fold)==3))
stopifnot(conditional_market_effect(6,0,c(-1,0),1)<0,
  conditional_market_effect(6,15,c(-1,0),1)>0,
  conditional_market_effect(6,0,c(-1,0),0)==0)
samples<-vapply(seq(.01,.99,length.out=99),function(u)
  conditional_market_effect(6,3,c(-1,0),1,uniform=u),numeric(1))
stopifnot(all(diff(samples)>=0),all(is.finite(samples)))
x<-c(0,1,4,7);y<-2
stopifnot(abs(empirical_crps(x,y)-(mean(abs(x-y))-.5*mean(abs(outer(x,x,'-')))))<1e-12)
cfg<-dget('experiments/configs/validate_shrinkage.R')
cfg$bootstrap_replicates<-1L;cfg$effect_draws<-1L;cfg$graphs_per_effect<-2L
cfg$prediction_burnin<-2048L;cfg$prediction_interval<-1024L
specs<-data.frame(network_id=c('held-a','held-b'),n_nodes=c(4,6))
parameters<-list(list(id='fixture',beta=c(-2,0,-.5,.5),alpha=c(-1,0),tau=.7))
p1<-prediction_graphs(specs,parameters,'new_market_uncertain',cfg,124L)
specs$n_links<-c(6,15)
p2<-prediction_graphs(specs,parameters,'new_market_uncertain',cfg,124L)
stopifnot(identical(p1,p2),nrow(p1)==4)
truth<-p1[1:2,];scores<-score_predictions(p1,truth,2L)
stopifnot(all(scores$n_draws==2),all(scores$crps>=-1e-10))
cat('PASS: reproducible size-only folds, effect posterior, CRPS, count-blind new-market prediction, valid graphs, and scoring.\n')
