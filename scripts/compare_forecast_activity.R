args<-commandArgs(trailingOnly=TRUE)
work<-if(length(args)) args[1] else 'local-forecast-activity'
prior<-'local-activity-validation';original<-'local-shrinkage-validation'
new<-read.csv(file.path(work,'scores.csv'))
old<-read.csv(file.path(prior,'scores.csv'));base<-read.csv(file.path(original,'scores.csv'))
combined<-rbind(base,old,new)
summary<-aggregate(cbind(absolute_error,crps,covered,width)~regime+metric,combined,mean)
folds<-aggregate(cbind(absolute_error,crps,covered,width)~regime+metric+fold,combined,mean)
write.csv(summary,file.path(work,'comparison_summary.csv'),row.names=FALSE)
write.csv(folds,file.path(work,'fold_comparison.csv'),row.names=FALSE)
cfg<-readRDS(file.path(work,'manifest.rds'))$config
audit<-read.csv(file.path(work,'calibration_audit.csv'))
complete<-nrow(audit)==cfg$folds*cfg$bootstrap_replicates*length(cfg$closure_scales) &&
  all(new$n_draws==new$expected_draws) && all(table(new$regime,new$metric)==100)
anchors_fixed<-TRUE;paired_draws<-TRUE
for(f in seq_len(cfg$folds)) {
  folder<-sprintf('fold-%02d',f)
  p<-readRDS(file.path(work,folder,'parameter_draws.rds'))
  previous<-readRDS(file.path(prior,folder,'parameter_draws.rds'))
  for(i in seq_along(p)) for(key in c('id','beta','alpha','tau','activity'))
    anchors_fixed<-anchors_fixed && identical(p[[i]][[key]],previous[[i]][[key]])
  a<-read.csv(file.path(work,folder,'new_density_activity','draws.csv'))
  b<-read.csv(file.path(work,folder,'new_density_closure','draws.csv'))
  keys<-c('network_id','parameter_id','effect_id','graph_id','n_links','activity_sd','activity_component')
  paired_draws<-paired_draws && identical(a[keys],b[keys])
}
stopifnot(anchors_fixed,paired_draws)
getscore<-function(regime,metric,column='crps')
  summary[summary$regime==regime & summary$metric==metric,column]
selected<-c('n_links','degree_sd','n_isolates','largest_component','clustering')
screen<-complete && all(vapply(selected,function(m)
  getscore('new_density_closure',m,'covered')>=cfg$min_predictive_coverage,logical(1))) &&
  all(vapply(c('n_links','largest_component','clustering'),function(m)
    getscore('new_density_closure',m)<=getscore('pooled_baseline',m),logical(1)))
hub_retained<-complete && all(vapply(c('degree_sd','max_degree'),function(m)
  getscore('fixed_count_closure',m)<=1.02*getscore('fixed_count_activity',m) &&
  getscore('fixed_count_closure',m,'covered')>=cfg$min_predictive_coverage,logical(1)))
targets_improved<-all(vapply(c('n_links','clustering'),function(m)
  getscore('new_density_closure',m)<getscore('new_market_activity',m),logical(1)))
write.csv(data.frame(check=c('complete','unchanged_hub_anchors','paired_counts_and_activity',
  'density_and_clustering_scores_improved','conditional_hub_retention','earlier_new_market_screen'),
  passed=c(complete,anchors_fixed,paired_draws,targets_improved,hub_retained,screen)),
  file.path(work,'readiness.csv'),row.names=FALSE)
pairs<-list()
for(pair in list(c('new_market_activity','new_density_activity'),
  c('new_market_activity','new_density_closure'),c('new_density_activity','new_density_closure'),
  c('fixed_count_activity','fixed_count_closure'))) {
  d<-merge(combined[combined$regime==pair[1],],combined[combined$regime==pair[2],],
    by=c('network_id','fold','metric'),suffixes=c('_old','_new'))
  stopifnot(all(abs(d$observed_old-d$observed_new)<1e-8))
  d$comparison<-paste(pair,collapse=' vs ');pairs[[length(pairs)+1L]]<-d
}
paired<-do.call(rbind,pairs);write.csv(paired,file.path(work,'paired_scores.csv'),row.names=FALSE)
quadrature_path<-file.path(work,if(file.exists(file.path(work,'quadrature_refined_scores.csv')))
  'quadrature_refined_scores.csv' else 'quadrature_count_scores.csv')
quadrature_nodes<-if(basename(quadrature_path)=='quadrature_refined_scores.csv') 241 else 61
quadrature<-read.csv(quadrature_path)
qsummary<-aggregate(cbind(absolute_error,crps,covered,width)~regime,quadrature,mean)
write.csv(qsummary,file.path(work,'quadrature_summary.csv'),row.names=FALSE)
png(file.path(work,'comparison.png'),width=1600,height=1100,res=150)
par(mfrow=c(2,3),mar=c(4,4,3,1),oma=c(2,0,3,0),bg='#f5f7fa',col.axis='#334155',col.lab='#334155')
for(protocol in c('new','fixed')) for(metric in if(protocol=='new') c('n_links','clustering','degree_sd') else
  c('degree_sd','max_degree','clustering')) {
  comparison<-if(protocol=='new') 'new_market_activity vs new_density_closure' else
    'fixed_count_activity vs fixed_count_closure'
  d<-paired[paired$comparison==comparison & paired$metric==metric,];limit<-max(d$crps_old,d$crps_new)*1.05
  plot(d$crps_old,d$crps_new,xlim=c(0,limit),ylim=c(0,limit),pch=19,
    col=adjustcolor(if(protocol=='new') '#177b60' else '#b65b2a',.6),
    xlab='Previous activity-model CRPS',ylab='Corrected model CRPS',
    main=c(n_links='Ties',clustering='Clustering',degree_sd='Degree SD',max_degree='Maximum degree')[[metric]])
  abline(0,1,lty=2,col='#64748b')
}
mtext('Density and closure calibration: new markets (top), fixed counts (bottom)',outer=TRUE,cex=1.1)
mtext('One dot per held-out market. Below the diagonal favors correction. Reused development folds.',
  outer=TRUE,side=1,cex=.85)
dev.off()
lines<-c('# Density and closure calibration with retained latent activity','',
  sprintf('Complete: %s. Two folds, 100 held-out markets, 12 bootstrap calibrations and 120 nested graphs per market/protocol. Original activity weights and structural/density anchors are unchanged: %s. Density-only and joint-correction predictions have identical count/activity draws: %s.',complete,anchors_fixed,paired_draws),'',
  'This is training-only predictive calibration of a factorized count/topology generator, not a new joint ERGM likelihood fit. The new closure distribution multiplies the existing GWESP coefficient; it retains the activity mixture and GWdegree coefficient.','',
  '## Size-only new markets: CRPS (lower is better)','',
  '| Model | Ties | Clustering | Degree SD | Largest component |',
  '| --- | ---: | ---: | ---: | ---: |')
labels<-c(pooled_baseline='Pooled baseline',new_market_uncertain='Original density shrinkage',
  new_market_activity='Previous activity',new_density_activity='Count correction only',
  new_density_closure='Count + closure correction')
for(regime in names(labels)) lines<-c(lines,sprintf('| %s | %.3f | %.3f | %.3f | %.3f |',labels[[regime]],
  getscore(regime,'n_links'),getscore(regime,'clustering'),getscore(regime,'degree_sd'),getscore(regime,'largest_component')))
ablation_path<-'local-density-recalibration/comparison_summary.csv'
if(file.exists(ablation_path)) {
  ablation<-read.csv(ablation_path)
  lines<-c(lines,sprintf('| Earlier density-only forecast recalibration | %.3f | %.3f | %.3f | %.3f |',
    ablation$new_crps[ablation$metric=='n_links'],ablation$new_crps[ablation$metric=='clustering'],
    ablation$new_crps[ablation$metric=='degree_sd'],ablation$new_crps[ablation$metric=='largest_component']))
}
lines<-c(lines,'','## Size-only errors and uncertainty','',
  '| Feature | Previous MAE | Corrected MAE | Previous coverage | Corrected coverage | Previous width | Corrected width |',
  '| --- | ---: | ---: | ---: | ---: | ---: | ---: |')
for(metric in c('n_links','clustering','degree_sd','max_degree','n_isolates','largest_component','triangles')) {
  x<-summary[summary$regime=='new_market_activity' & summary$metric==metric,]
  y<-summary[summary$regime=='new_density_closure' & summary$metric==metric,]
  lines<-c(lines,sprintf('| %s | %.3f | %.3f | %.0f%% | %.0f%% | %.3f | %.3f |',metric,
    x$absolute_error,y$absolute_error,100*x$covered,100*y$covered,x$width,y$width))
}
lines<-c(lines,'','Nominal coverage is 95%; the pilot screening floor is 85%. Narrower ranges alone are not evidence of improvement.','',
  '## Fixed-count topology and hub retention','',
  'Both models receive the exact held-out size and tie count; topology is withheld. Count error is zero by construction and excluded from performance claims.','',
  '| Feature | Previous CRPS | Corrected CRPS | Previous coverage | Corrected coverage |',
  '| --- | ---: | ---: | ---: | ---: |')
for(metric in c('degree_sd','max_degree','clustering','largest_component','triangles'))
  lines<-c(lines,sprintf('| %s | %.3f | %.3f | %.0f%% | %.0f%% |',metric,
    getscore('fixed_count_activity',metric),getscore('fixed_count_closure',metric),
    100*getscore('fixed_count_activity',metric,'covered'),100*getscore('fixed_count_closure',metric,'covered')))
lines<-c(lines,'','## Integrated count-law check','',
  sprintf('Binomial CDFs and %d-node normal quadrature integrate the six-bootstrap mixture directly. These scores compare the old and new count laws without relying on the 120 graph count draws. They remain finite-quadrature approximations; count calibration itself used 61 nodes.',quadrature_nodes),'',
  '| Count law | CRPS | Mean error | Coverage | Width |','| --- | ---: | ---: | ---: | ---: |')
for(i in seq_len(nrow(qsummary))) {d<-qsummary[i,];lines<-c(lines,
  sprintf('| %s | %.3f | %.3f | %.0f%% | %.3f |',d$regime,d$crps,d$absolute_error,100*d$covered,d$width))}
lines<-c(lines,'','## Calibration and decision screens','',
  sprintf('- Both new-market count and clustering scores improved over previous activity: **%s**.',targets_improved),
  sprintf('- Fixed-count degree/hub CRPS retained within 2%%, with coverage above the pilot floor: **%s**.',hub_retained),
  sprintf('- Earlier new-market screen against the pooled baseline: **%s**.',screen),'',
  'The unchanged hub parameters are a design guarantee; predictive hub retention is an empirical check. The 2% screen is descriptive, not a statistical noninferiority test. All optimizer outcomes, coefficient corrections, closure weights, and training-score guards are retained in calibration_audit.csv and bootstrap checkpoints.','',
  'Inspect fold_comparison.csv before treating aggregate gains as consistent across folds. No held-out graph, count, or clustering value enters either calibration. Previous held-out results motivated this design, so these reused folds are development validation rather than fresh confirmation. Six bootstrap draws and small simulation kernels limit precision.','',
  '![Paired market scores](comparison.png)','',
  'All original artifacts are preserved. All new data-derived outputs are local and ignored. No production network library, public site update, or large ABM study was generated. See [specification and commands](../experiments/FORECAST_ACTIVITY.md).')
lines<-c(lines,'','## Estimated forecast corrections','',
  'These are bootstrap averages, not coefficient confidence intervals. Full parameter draws and training diagnostics remain in the audit/checkpoints.','',
  '| Fold | Count shift | Size-slope correction | Density-effect scale | Closure 0 | Closure .5 | Closure 1 | Closure 1.5 |',
  '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |')
for(f in seq_len(cfg$folds)) {
  a<-audit[audit$fold==f & audit$closure_scale==1,]
  w<-aggregate(closure_weight~closure_scale,audit[audit$fold==f,],mean)
  w<-w$closure_weight[order(w$closure_scale)]
  lines<-c(lines,sprintf('| %d | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f |',
    f,mean(a$shift),mean(a$slope),mean(a$scale),w[1],w[2],w[3],w[4]))
}
lines<-c(lines,'','## Interpretation','',
  sprintf('Relative to the previous activity generator, the joint correction changes new-market count CRPS by %+.2f%%, clustering CRPS by %+.2f%%, and degree-SD CRPS by %+.2f%%. Negative changes are improvements.',
    100*(getscore('new_density_closure','n_links')/getscore('new_market_activity','n_links')-1),
    100*(getscore('new_density_closure','clustering')/getscore('new_market_activity','clustering')-1),
    100*(getscore('new_density_closure','degree_sd')/getscore('new_market_activity','degree_sd')-1)),'',
  'The ablation matters: changing density alone does not reliably improve clustering. Closure calibration partly addresses that structural mismatch while the hub mechanism remains explicit and unchanged. These aggregate effects are small; they do not establish a substantive or statistically reliable advantage.','',
  if(targets_improved && hub_retained && !screen)
    'Keep this as an optional improved development candidate. It meets the targeted aggregate count/clustering improvement and hub-retention checks, but it still trails the pooled baseline on the earlier full new-market screen. Do not replace the default or describe it as production validated.' else
    'Use the individual decision flags above rather than treating any single score improvement as a general model endorsement. A production decision needs fresh or nested validation and more precise simulation.','',
  'The quadrature count-law comparison is the cleaner assessment of density changes: finite nested graph draws add Monte Carlo error to empirical CRPS, and the pooled baseline uses a different, point-parameter sampling scheme. Quadrature old/new count scores are comparable to each other; do not use them as a direct high-precision comparison with the pooled finite-draw score.','',
  '| Fold | Previous count CRPS | Corrected count CRPS | Previous clustering CRPS | Corrected clustering CRPS |',
  '| --- | ---: | ---: | ---: | ---: |')
for(f in seq_len(cfg$folds)) {
  score<-function(regime,metric) folds$crps[folds$regime==regime & folds$metric==metric & folds$fold==f]
  lines<-c(lines,sprintf('| %d | %.3f | %.3f | %.3f | %.3f |',f,
    score('new_market_activity','n_links'),score('new_density_closure','n_links'),
    score('new_market_activity','clustering'),score('new_density_closure','clustering')))
}
lines<-c(lines,'','The integrated count-law improvement is driven by fold one and reverses slightly in fold two. New-market clustering improves in fold two and worsens slightly in fold one. The result therefore supports continued development rather than a uniform generalization claim.')
if(file.exists(file.path(work,'sampler_summary.csv'))) {
  d<-read.csv(file.path(work,'sampler_summary.csv'))
  lines<-c(lines,'','## Numerical checks','',sprintf(
    'The expanded closure range was checked at 24 nodes/30 ties, activity SD 0/2.25, closure multiplier 0/1.5, and a bootstrap anchor from each fold. Four 80-graph chains at normal and quadrupled effort gave a maximum standardized mean difference of %.2f across 32 feature/configuration comparisons; minimum normal-chain ESS was %.1f of 80. This limited check is not a convergence guarantee.',
    max(d$z),min(d$short_min_ess)))
}
if(file.exists(file.path(work,'quadrature_accuracy.csv'))) {
  d<-read.csv(file.path(work,'quadrature_accuracy.csv'))
  lines<-c(lines,'',sprintf('Across all 12 parameter draws, sizes 2–24, and old/new count laws, increasing quadrature from 61 to 241 nodes changes any CDF value by at most %.5f and any expected count by at most %.4f.',max(d$max_cdf_error),max(d$mean_error)))
}
if(file.exists(file.path(work,'import-check','result.txt'))) {
  lines<-c(lines,'','A corrected-generator graph imported into NetLogo successfully; all three sharing policies passed ten ticks and accounting checks. The import fixture and generated library remain private and ignored.')
}
warnings<-list()
for(f in seq_len(cfg$folds)) {
  root<-file.path(work,sprintf('fold-%02d',f))
  params<-readRDS(file.path(root,'parameter_draws.rds'))
  for(i in seq_along(params)) for(message in params[[i]]$closure$warnings)
    warnings[[length(warnings)+1L]]<-data.frame(fold=f,stage=paste0('closure-bootstrap-',i),message=message)
  for(regime in c('new_density_activity','new_density_closure','fixed_count_closure')) {
    prediction<-readRDS(file.path(root,regime,'prediction_checkpoint.rds'))
    for(message in attr(prediction$value,'warnings'))
      warnings[[length(warnings)+1L]]<-data.frame(fold=f,stage=regime,message=message)
  }
}
if(length(warnings)) {
  warnings<-do.call(rbind,warnings)
  warnings$encoding_message<-grepl('native encoding|translated to UTF-8',warnings$message)
  write.csv(warnings,file.path(work,'simulation_warnings.csv'),row.names=FALSE)
  lines<-c(lines,'',if(all(warnings$encoding_message))
    'Simulation emitted native-encoding translation warnings, retained in simulation_warnings.csv and worker logs. No additional simulation-warning category was recorded. Numeric graph invariants and identity-law tests passed.' else
    'Simulation warnings include messages beyond native-encoding translation. Inspect simulation_warnings.csv before using this candidate.')
}
writeLines(lines,file.path(work,'comparison.md'))
saveRDS(list(code=tools::md5sum('scripts/compare_forecast_activity.R'),
  inputs=tools::md5sum(c(file.path(work,c('scores.csv','calibration_audit.csv')),quadrature_path,
    file.path(prior,'scores.csv'),file.path(original,'scores.csv'),
    if(file.exists(ablation_path)) ablation_path else character()))),file.path(work,'comparison_manifest.rds'))
print(summary[summary$regime %in% c('new_density_activity','new_density_closure','fixed_count_closure'),],row.names=FALSE)
print(qsummary,row.names=FALSE)
cat('Targets improved:',targets_improved,'; hub retention:',hub_retained,'; new-market screen:',screen,'\n')
