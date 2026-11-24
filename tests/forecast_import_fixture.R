for(h in c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R','activity_ergm_functions.R'))
  source(file.path('scripts',h))
suppressPackageStartupMessages(library(ergm))
work<-'local-forecast-activity/import-check';dir.create(work,recursive=TRUE,showWarnings=FALSE)
dir.create(file.path(work,'synthetic-networks'),showWarnings=FALSE)
cfg<-dget('experiments/configs/forecast_activity.R')
p<-readRDS('local-forecast-activity/fold-01/parameter_draws.rds')[[1]]
set.seed(1201001);n<-10
sigma<-p$activity$scales[-1][which.max(p$activity$weights[-1])]
q<-min(p$closure$scales[p$closure$weights>.05])
law<-p$count_law
probability<-plogis(p$alpha[1]+p$alpha[2]*log(n)+law$shift+
  law$slope*(log(n)-law$center)+rnorm(1,0,p$tau)*law$scale)
m<-rbinom(1,choose(n,2),probability)
beta<-p$beta;beta[4]<-beta[4]*q
net<-activity_graphs(n,m,rnorm(n,0,sigma),beta,1,cfg,1201002)[[1]]
invisible(export_mutual_draws(list(net),data.frame(generator='forecast-calibrated-activity',
  seed=1201002,activity_sd=sigma,closure_scale=q),file.path(work,'synthetic-networks')))
invisible(file.copy('MobileBankMarkets_v1.nlogox',file.path(work,'MobileBankMarkets_v1.nlogox'),overwrite=TRUE))
stopifnot(file.exists('fetch/fetch.jar')) # Install with scripts/install_netlogo_fetch.py.
dir.create(file.path(work,'fetch'),showWarnings=FALSE)
invisible(file.copy('fetch/fetch.jar',file.path(work,'fetch','fetch.jar'),overwrite=TRUE))
stats<-activity_statistics(net)
write.csv(as.data.frame(t(stats)),file.path(work,'expected.csv'),row.names=FALSE)
cat('Import fixture:',stats[['n_nodes']],'nodes,',stats[['n_links']],'ties,',stats[['n_isolates']],
    'isolates; activity SD',sigma,'and closure multiplier',q,'\n')
