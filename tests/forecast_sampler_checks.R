# Test the new closure range; independent chains and longer sampling effort.
for(h in c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R','activity_ergm_functions.R'))
  source(file.path('scripts',h))
suppressPackageStartupMessages(library(ergm))
cfg<-dget('experiments/configs/forecast_activity.R');work<-'local-forecast-activity'
cases<-expand.grid(sigma=c(0,2.25),closure=c(0,1.5),fold=1:2)
rows<-list();index<-0L
for(i in seq_len(nrow(cases))) {
  case<-cases[i,]
  p<-readRDS(file.path('local-activity-validation',sprintf('fold-%02d',case$fold),'parameter_draws.rds'))[[1]]
  beta<-p$beta;beta[4]<-beta[4]*case$closure
  set.seed(1101001+i);activity<-rnorm(24,0,case$sigma)
  for(multiplier in c(1,4)) for(chain in 1:4) {
    settings<-cfg;settings$activity_burnin<-cfg$activity_burnin*multiplier
    settings$activity_interval<-cfg$activity_interval*multiplier
    draws<-activity_graphs(24,30,activity,beta,80,settings,1102001+i*100+chain)
    stats<-as.data.frame(do.call(rbind,lapply(draws,activity_statistics)))
    for(metric in c('degree_sd','max_degree','clustering','triangles')) {
      x<-stats[[metric]]
      index<-index+1L;rows[[index]]<-data.frame(case=i,sigma=case$sigma,closure=case$closure,
        fold=case$fold,multiplier=multiplier,chain=chain,metric=metric,mean=mean(x),sd=sd(x),
        ess=if(sd(x)<1e-10) length(x) else as.numeric(coda::effectiveSize(x)))
    }
  }
}
d<-do.call(rbind,rows);write.csv(d,file.path(work,'sampler_chains.csv'),row.names=FALSE)
groups<-unique(d[c('case','metric')]);summary<-do.call(rbind,lapply(seq_len(nrow(groups)),function(i) {
  x<-d[d$case==groups$case[i] & d$metric==groups$metric[i],]
  a<-x[x$multiplier==1,];b<-x[x$multiplier==4,]
  se<-sqrt(var(a$mean)/4+var(b$mean)/4)
  data.frame(case=groups$case[i],metric=groups$metric[i],short_mean=mean(a$mean),long_mean=mean(b$mean),
    difference=mean(a$mean)-mean(b$mean),difference_se=se,
    z=if(se>0) abs(mean(a$mean)-mean(b$mean))/se else 0,
    short_min_ess=min(a$ess),long_min_ess=min(b$ess))
}))
write.csv(summary,file.path(work,'sampler_summary.csv'),row.names=FALSE)
cat('Largest standardized chain-length difference:',max(summary$z),
    '; minimum short-chain ESS:',min(summary$short_min_ess),'of 80\n')
