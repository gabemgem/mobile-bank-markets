# Limited chain-length sensitivity check, not proof of convergence.
for(h in c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R','activity_ergm_functions.R'))
  source(file.path('scripts',h))
suppressPackageStartupMessages(library(ergm))
work<-'local-activity-validation';cfg<-dget('experiments/configs/activity_validation.R')
cases<-expand.grid(n=c(10,24),sigma=c(0,2.25),fold=1:2)
rows<-list();index<-0L
for(i in seq_len(nrow(cases))) {
  case<-cases[i,];n<-case$n;m<-if(n==10) 8 else 30
  beta<-readRDS(file.path('local-shrinkage-validation',sprintf('fold-%02d',case$fold),'parameter_draws.rds'))[[1]]$beta
  set.seed(701001+i);activity<-rnorm(n,0,case$sigma)
  for(multiplier in c(1,4)) for(chain in 1:4) {
    settings<-cfg;settings$activity_burnin<-cfg$activity_burnin*multiplier
    settings$activity_interval<-cfg$activity_interval*multiplier
    draws<-activity_graphs(n,m,activity,beta,80,settings,702001+i*100+chain)
    stats<-as.data.frame(do.call(rbind,lapply(draws,activity_statistics)))
    for(metric in c('degree_sd','max_degree','clustering','triangles')) {
      x<-stats[[metric]];ess<-if(sd(x)<1e-10) length(x) else as.numeric(coda::effectiveSize(x))
      index<-index+1L;rows[[index]]<-data.frame(case=i,n=n,m=m,sigma=case$sigma,fold=case$fold,
        multiplier=multiplier,chain=chain,metric=metric,mean=mean(x),sd=sd(x),ess=ess)
    }
  }
}
d<-do.call(rbind,rows);write.csv(d,file.path(work,'mixing_chains.csv'),row.names=FALSE)
groups<-unique(d[c('case','metric')]);summary<-do.call(rbind,lapply(seq_len(nrow(groups)),function(i) {
  x<-d[d$case==groups$case[i] & d$metric==groups$metric[i],]
  short<-x[x$multiplier==1,];long<-x[x$multiplier==4,]
  # Across-chain mean differences reflect both starts and Monte Carlo variation.
  se<-sqrt(var(short$mean)/4+var(long$mean)/4)
  data.frame(case=groups$case[i],metric=groups$metric[i],short_mean=mean(short$mean),
    long_mean=mean(long$mean),difference=mean(short$mean)-mean(long$mean),
    difference_se=se,z=if(se>0) abs(mean(short$mean)-mean(long$mean))/se else 0,
    short_min_ess=min(short$ess),long_min_ess=min(long$ess))
}))
write.csv(summary,file.path(work,'mixing_summary.csv'),row.names=FALSE)
print(summary,row.names=FALSE)
cat('Largest standardized chain-length difference:',max(summary$z),'\n')
