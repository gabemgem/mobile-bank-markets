for(h in c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R','activity_ergm_functions.R',
  'forecast_activity_functions.R')) source(file.path('scripts',h))
work<-'local-forecast-activity';cfg<-dget('experiments/configs/forecast_activity.R')
fine<-cfg;fine$count_quadrature<-241L
rows<-list();index<-0L
for(f in seq_len(cfg$folds)) {
  params<-readRDS(file.path(work,sprintf('fold-%02d',f),'parameter_draws.rds'))
  for(p in seq_along(params)) for(n in 2:24) for(corrected in c(FALSE,TRUE)) {
    a<-forecast_count_cdf(n,params[[p]],cfg,corrected)
    b<-forecast_count_cdf(n,params[[p]],fine,corrected)
    index<-index+1L;rows[[index]]<-data.frame(fold=f,bootstrap=p,n_nodes=n,
      corrected=corrected,max_cdf_error=max(abs(a-b)),mean_error=abs(sum(1-a)-sum(1-b)))
  }
}
d<-do.call(rbind,rows);write.csv(d,file.path(work,'quadrature_accuracy.csv'),row.names=FALSE)
stopifnot(max(d$max_cdf_error)<.01)
cat('PASS: 61 versus 241 quadrature nodes; maximum CDF error',max(d$max_cdf_error),
    '; maximum expected-count difference',max(d$mean_error),'\n')
nets<-read_mutual_library('data');rows<-list();errors<-list();index<-0L
for(f in seq_len(cfg$folds)) {
  root<-file.path(work,sprintf('fold-%02d',f))
  params<-readRDS(file.path(root,'parameter_draws.rds'))
  ids<-readRDS(file.path(root,'membership.rds'))$test
  for(id in ids) for(corrected in c(FALSE,TRUE)) {
    n<-network::network.size(nets[[id]]);m<-network::network.edgecount(nets[[id]])
    support<-0:choose(n,2);step<-as.numeric(support>=m)
    coarse<-rowMeans(vapply(params,function(p) forecast_count_cdf(n,p,cfg,corrected),numeric(length(support))))
    refined<-rowMeans(vapply(params,function(p) forecast_count_cdf(n,p,fine,corrected),numeric(length(support))))
    lower<-support[which(refined>=.025)[1]];upper<-support[which(refined>=.975)[1]]
    index<-index+1L
    rows[[index]]<-data.frame(network_id=id,fold=f,
      regime=if(corrected) 'corrected_count' else 'previous_count',observed=m,
      mean=sum(1-refined),crps=sum((refined-step)^2),q025=lower,q975=upper,
      covered=m>=lower && m<=upper,width=upper-lower,absolute_error=abs(sum(1-refined)-m))
    errors[[index]]<-data.frame(network_id=id,fold=f,corrected=corrected,
      coarse_crps=sum((coarse-step)^2),refined_crps=sum((refined-step)^2))
  }
}
write.csv(do.call(rbind,rows),file.path(work,'quadrature_refined_scores.csv'),row.names=FALSE)
errors<-do.call(rbind,errors);errors$change<-errors$refined_crps-errors$coarse_crps
write.csv(errors,file.path(work,'quadrature_score_accuracy.csv'),row.names=FALSE)
print(aggregate(change~corrected,errors,mean),row.names=FALSE)
