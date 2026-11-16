for(h in c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R',
  'shrinkage_mutual_ergm_functions.R','validate_shrinkage_functions.R','activity_ergm_functions.R',
  'forecast_activity_functions.R','nested_network_functions.R')) source(file.path('scripts',h))
cfg<-dget('experiments/configs/nested_network_validation.R')
nets<-lapply(rep(2:9,3),function(n) network::network.initialize(n,directed=FALSE))
names(nets)<-sprintf('market-%02d',seq_along(nets))
plan<-nested_splits(nets,cfg)
stopifnot(identical(plan,nested_splits(nets,cfg)),all(table(plan$outer$fold)==8))
for(s in plan$splits) for(i in 1:2) {
  validation<-s$inner$network_id[s$inner$fold==i];train<-setdiff(s$train,validation)
  stopifnot(!length(intersect(train,c(s$test,validation))),!length(intersect(validation,s$test)))
}
x<-c(0,1,4,7);y<-2
fair<-mean(abs(x-y))-.5*sum(abs(outer(x,x,'-')))/(length(x)*(length(x)-1))
stopifnot(abs(nested_crps(x,y,rep('p',4),1:4)-fair)<1e-12)
# Duplicating a correlated draw inside its group must not create new independent pairs.
stopifnot(abs(nested_crps(rep(x,each=3),y,rep('p',12),rep(1:4,each=3))-fair)<1e-12)
p<-rep(c('a','b'),each=4);e<-rep(1:4,2);z<-c(x,x+1)
within<-function(v) sum(abs(outer(v,v,'-')))/12
expected<-mean(abs(z-y))-.5*(within(x)+within(x+1)+2*mean(abs(outer(x,x+1,'-'))))/4
stopifnot(abs(nested_crps(z,y,p,e)-expected)<1e-12)
scales<-nested_scales(nets,cfg);stopifnot(all(is.finite(scales)),all(scales>0))
fixture<-expand.grid(network_id=letters[1:10],metric=cfg$selection_metrics,
  regime=c('pooled','corrected_hub'),stringsAsFactors=FALSE)
fixture$scaled_crps<-ifelse(fixture$regime=='pooled',1,.9)
stopifnot(nested_select(fixture,cfg)$selected=='corrected_hub')
fixture$scaled_crps<-1
stopifnot(nested_select(fixture,cfg)$selected=='pooled')
cat('PASS: nested disjoint/reproducible folds, grouped fair CRPS, bootstrap mixture weights, finite training scales, simplicity selection.\n')
