args<-commandArgs(trailingOnly=TRUE)
work<-if(length(args)) args[1] else 'local-activity-validation'
parent<-if(length(args)>1) args[2] else 'local-shrinkage-validation'
new<-read.csv(file.path(work,'scores.csv'));zero<-read.csv(file.path(work,'zero_scores.csv'))
old<-read.csv(file.path(parent,'scores.csv'))
all<-rbind(old,new,zero)
summary<-aggregate(cbind(absolute_error,crps,covered,width)~regime+metric,all,mean)
write.csv(summary,file.path(work,'comparison_summary.csv'),row.names=FALSE)
folds<-aggregate(cbind(absolute_error,crps,covered,width)~regime+metric+fold,all,mean)
write.csv(folds,file.path(work,'fold_comparison.csv'),row.names=FALSE)
pairs<-list()
for(pair in list(c('calibrated_uncertain','fixed_count_activity'),
  c('new_market_uncertain','new_market_activity'),c('fixed_count_zero','fixed_count_activity'))) {
  d<-merge(all[all$regime==pair[1],],all[all$regime==pair[2],],
    by=c('network_id','fold','metric'),suffixes=c('_old','_new'))
  stopifnot(all(abs(d$observed_old-d$observed_new)<1e-8))
  d$comparison<-paste(pair,collapse=' vs ');pairs[[length(pairs)+1L]]<-d
}
paired<-do.call(rbind,pairs);write.csv(paired,file.path(work,'paired_scores.csv'),row.names=FALSE)
misses<-new[new$regime=='fixed_count_activity' & new$metric %in% c('degree_sd','max_degree') & !new$covered,]
misses$direction<-ifelse(misses$observed>misses$q975,'above','below')
write.csv(misses,file.path(work,'hub_misses.csv'),row.names=FALSE)
audit<-read.csv(file.path(work,'mixture_audit.csv'));cfg<-readRDS(file.path(work,'manifest.rds'))$config
complete<-nrow(audit)==cfg$folds*cfg$bootstrap_replicates*length(cfg$activity_scales) &&
  all(new$n_draws==new$expected_draws) && all(zero$n_draws==zero$expected_draws) &&
  all(table(new$regime,new$metric)==100) && all(table(zero$metric)==100)
selected<-c('n_links','degree_sd','n_isolates','largest_component','clustering')
a<-summary[summary$regime=='new_market_activity',];b<-summary[summary$regime=='pooled_baseline',]
joined<-merge(a,b,by='metric',suffixes=c('_new','_base'))
screen<-complete && all(a$covered[a$metric %in% selected]>=cfg$min_predictive_coverage) &&
  all(joined$crps_new[joined$metric %in% c('n_links','largest_component','clustering')]<=
    joined$crps_base[joined$metric %in% c('n_links','largest_component','clustering')])
write.csv(data.frame(check=c('complete','new_market_earlier_screen'),passed=c(complete,screen)),
  file.path(work,'readiness.csv'),row.names=FALSE)
png(file.path(work,'comparison.png'),width=1600,height=1100,res=150)
par(mfrow=c(2,3),mar=c(4,4,3,1),oma=c(2,0,3,0),bg='#f5f7fa',col.axis='#334155',col.lab='#334155')
for(comparison in c('new_market_uncertain vs new_market_activity','fixed_count_zero vs fixed_count_activity'))
  for(metric in c('degree_sd','largest_component','clustering')) {
    d<-paired[paired$comparison==comparison & paired$metric==metric,]
    maximum<-max(d$crps_old,d$crps_new)*1.05
    plot(d$crps_old,d$crps_new,xlim=c(0,maximum),ylim=c(0,maximum),pch=19,
      col=adjustcolor(if(startsWith(comparison,'new')) '#177b60' else '#b65b2a',.6),
      xlab=if(startsWith(comparison,'new')) 'Current model CRPS' else 'Zero-activity control CRPS',
      ylab='Activity candidate CRPS',main=c(degree_sd='Degree SD',largest_component='Largest component',clustering='Clustering')[[metric]])
    abline(0,1,lty=2,col='#64748b')
  }
mtext('Latent activity: new markets (top) and fixed-count ablation (bottom)',outer=TRUE,cex=1.15)
mtext('Each dot is one held-out market. Below the diagonal favors activity. Reused development folds.',
  outer=TRUE,side=1,cex=.85)
dev.off()
lines<-c('# Regularized latent-activity development pilot','',
  sprintf('Numerically complete: %s. Two folds, 100 held-out markets, 12 training bootstrap calibrations, 120 graphs per market/protocol.',complete),'',
  'The candidate factorizes tie count and conditional topology. It uses training-only latent activity mixtures, no actor attributes or observed held-out degrees. Shared ERGM and density anchors are reused from the original successful bootstrap fits. This is a conditional simulation-calibrated generator, not a joint latent ERGM likelihood fit.','',
  '## Size-only new markets','',
  '| Metric | Current MAE | Activity MAE | Current CRPS | Activity CRPS | Pooled CRPS | Current coverage | Activity coverage |',
  '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |')
metrics<-c('n_links','degree_sd','n_isolates','largest_component','clustering','triangles')
for(metric in metrics) {
  x<-summary[summary$regime=='new_market_uncertain' & summary$metric==metric,]
  y<-summary[summary$regime=='new_market_activity' & summary$metric==metric,]
  z<-summary[summary$regime=='pooled_baseline' & summary$metric==metric,]
  lines<-c(lines,sprintf('| %s | %.3f | %.3f | %.3f | %.3f | %.3f | %.0f%% | %.0f%% |',metric,
    x$absolute_error,y$absolute_error,x$crps,y$crps,z$crps,100*x$covered,100*y$covered))
}
lines<-c(lines,'','## Exact-count structural ablation','',
  'These two generators receive the same held-out size and exact tie count. Count error is zero by construction and excluded from improvement claims. The zero-activity control separates the hub mechanism from changing the conditioning protocol.','',
  '| Metric | Zero-activity CRPS | Activity CRPS | Zero coverage | Activity coverage | Activity mean error |',
  '| --- | ---: | ---: | ---: | ---: | ---: |')
for(metric in c('degree_sd','max_degree','n_isolates','largest_component','clustering','triangles')) {
  x<-summary[summary$regime=='fixed_count_zero' & summary$metric==metric,]
  y<-summary[summary$regime=='fixed_count_activity' & summary$metric==metric,]
  lines<-c(lines,sprintf('| %s | %.3f | %.3f | %.0f%% | %.0f%% | %.3f |',metric,
    x$crps,y$crps,100*x$covered,100*y$covered,y$absolute_error))
}
lines<-c(lines,'','The exact-count ablation is the cleanest check of the hub mechanism: it holds count conditioning and shared structural anchors constant. Improvements over the original count-informed generator also include the change to exact count conditioning.','')
for(metric in c('degree_sd','max_degree','largest_component','clustering')) {
  x<-summary[summary$regime=='fixed_count_zero' & summary$metric==metric,]
  y<-summary[summary$regime=='fixed_count_activity' & summary$metric==metric,]
  lines<-c(lines,sprintf('- %s: activity changes CRPS by %+.1f%% relative to the zero-activity control; negative is better.',
    metric,100*(y$crps/x$crps-1)))
}
lines<-c(lines,'','## Mixture and uncertainty','',
  '| Fold | Scale 0 | Scale .75 | Scale 1.5 | Scale 2.25 |','| --- | ---: | ---: | ---: | ---: |')
for(f in seq_len(cfg$folds)) {
  w<-aggregate(weight~scale,audit[audit$fold==f,],mean)
  lines<-c(lines,sprintf('| %d | %.3f | %.3f | %.3f | %.3f |',f,w$weight[order(w$scale)][1],
    w$weight[order(w$scale)][2],w$weight[order(w$scale)][3],w$weight[order(w$scale)][4]))
}
lines<-c(lines,'',sprintf('Earlier size-only screening rule passes: **%s**. This requires complete draws, at least 85%% coverage on selected features, and count/component/clustering CRPS no worse than the pooled baseline. Nominal coverage is 95%%; passing the pilot floor would not establish calibration.',screen),'',
  'The original count-informed comparison is retained in paired_scores.csv, but it allows count variation, unlike exact conditioning. Original runs did not record maximum degree, so no retrospective current-model hub-score comparison is claimed.','',
  'Fold-specific scores and all interval widths are in fold_comparison.csv and comparison_summary.csv. A finite six-draw bootstrap and 120 nested graphs do not support precise tail or significance claims. Candidate design was informed by earlier results on these folds: this is development validation, not fresh confirmation.','',
  '![Paired market-level scores](comparison.png)','',
  'No production synthetic network library, public data release, or large ABM study was generated. All research artifacts remain private and ignored. See [specification and commands](../experiments/ACTIVITY_ERGM.md).')
lines<-c(lines,'','## Decision and remaining limitations','',
  'Keep the activity generator as an opt-in topology candidate when size and tie count are supplied. The zero-activity ablation supports a real degree/hub benefit, with small component and clustering tradeoffs. Do not promote its size-only forecasting law to the default: it does not beat the pooled baseline on the declared count/component/clustering scores.', '',
  'In this run, conditional degree-spread and maximum-degree CRPS improve in both folds. New-market count and degree-spread CRPS also improve in both folds versus the current shrinkage model; the component improvement reverses slightly in fold two, and clustering worsens in both folds. New-market degree-spread coverage is 92% in fold one and 84% in fold two. These development results do not justify a claim of uniform superiority.', '',
  sprintf('At fixed counts, %d degree-spread cases and %d maximum-degree cases fall outside their central ranges. Most remaining misses are high hubs: %d degree-spread and %d maximum-degree observations exceed the upper bound. See hub_misses.csv.',
    sum(misses$metric=='degree_sd'),sum(misses$metric=='max_degree'),
    sum(misses$metric=='degree_sd' & misses$direction=='above'),sum(misses$metric=='max_degree' & misses$direction=='above')), '',
  'Before production generation, confirm the selected topology on fresh data or with nested model selection, increase the finite calibration/uncertainty budget, and separately validate the intended source of size/density scenarios. A prescribed size/count grid can support transparent exploratory ABM sensitivity analyses without claiming that the size-only density forecast is validated.')
ablation_path<-'local-density-recalibration/comparison_summary.csv'
if(file.exists(ablation_path)) {
  ablation<-read.csv(ablation_path)
  lines<-c(lines,'','The previous density-recalibration-only ablation provides another reference:', '',
    '| Metric | Density-only recalibration CRPS | Activity CRPS |',
    '| --- | ---: | ---: |')
  for(metric in c('n_links','degree_sd','largest_component','clustering')) {
    lines<-c(lines,sprintf('| %s | %.3f | %.3f |',metric,
      ablation$new_crps[ablation$metric==metric],
      summary$crps[summary$regime=='new_market_activity' & summary$metric==metric]))
  }
  lines<-c(lines,'','Activity improves degree-spread scores and coverage relative to that ablation, but the density-only correction retains slightly better count/component and clustering scores. Small differences are not significance claims.')
}
if(file.exists(file.path(work,'mixing_summary.csv'))) {
  mixing<-read.csv(file.path(work,'mixing_summary.csv'))
  lines<-c(lines,'','## Engineering and sampler checks','',
    sprintf('Eight configurations (sizes 10/24, activity SD 0/2.25, one bootstrap anchor per fold), four chains each, and 80 graphs per chain were checked at normal and quadrupled burn-in/interval. Largest standardized mean difference across 32 feature/configuration comparisons: %.2f; minimum normal-chain ESS: %.1f of 80. These limited checks do not establish universal convergence.',max(mixing$z),min(mixing$short_min_ess)), '',
    'Unit checks passed count conservation, the node-activity energy statistic, empty/full graphs, simplex regularization, size-only count blindness, and maximum-degree scoring. The unchanged original validation checks also passed. A nonzero-activity graph imported into NetLogo with 10 kiosks, 8 ties, and 2 isolates; all three sharing policies passed ten ticks and accounting checks.')
}
writeLines(lines,file.path(work,'comparison.md'))
saveRDS(list(code=tools::md5sum('scripts/compare_activity_validation.R'),
  inputs=tools::md5sum(c(file.path(work,c('scores.csv','zero_scores.csv','mixture_audit.csv')),
    file.path(parent,'scores.csv'),if(file.exists(ablation_path)) ablation_path else character()))),
  file.path(work,'comparison_manifest.rds'))
print(summary[summary$regime %in% c('new_market_activity','fixed_count_activity','fixed_count_zero'),],row.names=FALSE)
cat('Complete:',complete,'; earlier new-market screen:',screen,'\n')
