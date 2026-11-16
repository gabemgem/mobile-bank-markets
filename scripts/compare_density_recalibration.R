args<-commandArgs(trailingOnly=TRUE)
work<-if(length(args)) args[1] else 'local-density-recalibration'
parent<-if(length(args)>1) args[2] else 'local-shrinkage-validation'
new<-read.csv(file.path(work,'scores.csv'));original<-read.csv(file.path(parent,'scores.csv'))
old<-original[original$regime=='new_market_uncertain',]
paired<-merge(old,new,by=c('network_id','fold','regime','metric'),suffixes=c('_old','_new'))
stopifnot(nrow(paired)==nrow(old),all(abs(paired$observed_old-paired$observed_new)<1e-10))
audit<-read.csv(file.path(work,'calibration_audit.csv'))
cfg<-readRDS(file.path(work,'manifest.rds'))$config
complete<-nrow(audit)==cfg$folds*cfg$bootstrap_replicates && all(audit$admitted) &&
  all(new$n_draws==new$expected_draws)
write.csv(paired,file.path(work,'paired_scores.csv'),row.names=FALSE)
summary<-do.call(rbind,lapply(unique(old$metric),function(metric) {
  a<-old[old$metric==metric,];b<-new[new$metric==metric,]
  baseline<-original[original$regime=='pooled_baseline' & original$metric==metric,]
  data.frame(metric=metric,n=nrow(b),old_mae=mean(a$absolute_error),new_mae=mean(b$absolute_error),
    old_crps=mean(a$crps),new_crps=mean(b$crps),baseline_crps=mean(baseline$crps),
    old_coverage=mean(a$covered),new_coverage=mean(b$covered),
    old_width=mean(a$width),new_width=mean(b$width))
}))
write.csv(summary,file.path(work,'comparison_summary.csv'),row.names=FALSE)
fold_summary<-rbind(transform(aggregate(cbind(absolute_error,crps,covered,width)~fold+metric,old,mean),version='original'),
  transform(aggregate(cbind(absolute_error,crps,covered,width)~fold+metric,new,mean),version='recalibrated'))
write.csv(fold_summary,file.path(work,'fold_comparison.csv'),row.names=FALSE)
selected<-summary[summary$metric %in% c('n_links','degree_sd','n_isolates','largest_component','clustering'),]
screen<-complete && all(selected$new_coverage>=cfg$min_predictive_coverage) &&
  all(summary$new_crps[summary$metric %in% c('n_links','largest_component','clustering')] <=
      summary$baseline_crps[summary$metric %in% c('n_links','largest_component','clustering')])
print(summary,row.names=FALSE)
cat('All calibration/prediction draws complete:',complete,'; new-market pilot screen:',screen,'\n')
write.csv(data.frame(check=c('complete_calibration_and_prediction_audit','new_market_pilot_screen'),
  passed=c(complete,screen)),file.path(work,'readiness.csv'),row.names=FALSE)
png(file.path(work,'comparison.png'),width=1500,height=1100,res=150)
par(mfrow=c(2,2),mar=c(4,4,3,1),oma=c(2,0,2,0),bg='#f5f7fa',col.axis='#334155',col.lab='#334155')
for(metric in c('n_links','largest_component','degree_sd')) {
  d<-paired[paired$metric==metric,];maximum<-max(d$crps_old,d$crps_new)
  plot(d$crps_old,d$crps_new,xlim=c(0,maximum*1.05),ylim=c(0,maximum*1.05),
    pch=19,col=adjustcolor('#177b60',.6),xlab='Original CRPS',ylab='Recalibrated CRPS',
    main=c(n_links='Ties',largest_component='Largest component',degree_sd='Degree SD')[[metric]])
  abline(0,1,lty=2,col='#64748b')
}
d<-paired[paired$metric=='n_links',];maximum<-max(d$width_old,d$width_new)
plot(d$width_old,d$width_new,xlim=c(0,maximum*1.05),ylim=c(0,maximum*1.05),pch=19,
  col=adjustcolor('#b65b2a',.6),xlab='Original count range width',ylab='Recalibrated width',
  main='Central 95% count range width')
abline(0,1,lty=2,col='#64748b')
mtext('Density recalibration only: unchanged structural fits and held-out markets',outer=TRUE,cex=1.15)
mtext('Below the diagonal means a lower score or narrower range; narrowing alone does not establish better calibration.',
      outer=TRUE,side=1,cex=.85)
dev.off()
text<-c('# Predictive density recalibration without changing the degree specification','',
  'This ablation retains all original training-only ERGM fits and joint bootstrap parameter draws. It recalibrates only the new-market density-effect mean and scale, separately inside every training bootstrap. No structural fit is repeated and no held-out count or topology is used in predictive calibration.', '',
  sprintf('All %d calibration draws admitted; complete planned graph counts: %s. This is a development comparison on reused folds, not fresh confirmation.',nrow(audit),complete),'',
  '| Metric | Original MAE | Recalibrated MAE | Original CRPS | Recalibrated CRPS | Original coverage | Recalibrated coverage |',
  '| --- | ---: | ---: | ---: | ---: | ---: | ---: |')
for(i in seq_len(nrow(summary))) {
  d<-summary[i,]
  text<-c(text,sprintf('| %s | %.3f | %.3f | %.3f | %.3f | %.0f%% | %.0f%% |',d$metric,d$old_mae,d$new_mae,
    d$old_crps,d$new_crps,100*d$old_coverage,100*d$new_coverage))
}
text<-c(text,'','![Paired predictive comparison](comparison.png)','','## Interpretation','',
  'The mean/scale correction gives a modest proper-score improvement for size-only markets and narrows excessive count ranges. It does not solve degree/hub undercoverage; tighter density variation can expose remaining structural mismatch previously hidden by broad ranges.', '',
  paste0('The unchanged new-market pilot screen passes: ',screen,
    '. Passing would still support only an exploratory development candidate, not production certification.'),'',
  'Inspect coverage against nominal 95% and the declared 85% pilot floor, and compare with the simpler pooled baseline as well as the previous density-shrinkage model. Six bootstrap draws per fold leave substantial Monte Carlo and estimation uncertainty. No significance or fresh-validation claim is made.', '',
  'Density-informed protocols are unchanged by this ablation. The generator remains a two-stage empirical-Bayes approximation with a simulation-based forecast correction; it is not a full hierarchical Bayesian ERGM.', '',
  'All original fit objects remain unchanged and are identified by hashes in calibration_audit.csv. All data-derived outputs are local and ignored; no production network library or large ABM study was generated.', '',
  'See the [revised pipeline guide](../experiments/REVISED_SHRINKAGE.md).')
writeLines(text,file.path(work,'comparison.md'))
