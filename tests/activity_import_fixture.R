for(h in c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R','activity_ergm_functions.R'))
  source(file.path('scripts',h))
suppressPackageStartupMessages(library(ergm))
work<-'local-activity-validation/import-check';dir.create(work,recursive=TRUE,showWarnings=FALSE)
dir.create(file.path(work,'synthetic-networks'),showWarnings=FALSE)
cfg<-dget('experiments/configs/activity_validation.R')
p<-readRDS('local-activity-validation/fold-01/parameter_draws.rds')[[1]]
set.seed(801001);sigma<-p$activity$scales[-1][which.max(p$activity$weights[-1])]
net<-activity_graphs(10,8,rnorm(10,0,sigma),p$beta,1,cfg,801002)[[1]]
record<-data.frame(generator='conditional-latent-activity',seed=801002,activity_sd=sigma)
export_mutual_draws(list(net),record,file.path(work,'synthetic-networks'))
file.copy('MobileBankMarkets_v1.nlogox',file.path(work,'MobileBankMarkets_v1.nlogox'),overwrite=TRUE)
stopifnot(file.exists('fetch/fetch.jar')) # Install with scripts/install_netlogo_fetch.py.
dir.create(file.path(work,'fetch'),showWarnings=FALSE)
file.copy('fetch/fetch.jar',file.path(work,'fetch','fetch.jar'),overwrite=TRUE)
stats<-activity_statistics(net)
write.csv(as.data.frame(t(stats)),file.path(work,'expected.csv'),row.names=FALSE)
cat(stats[['n_nodes']],stats[['n_links']],stats[['n_isolates']],'\n')
