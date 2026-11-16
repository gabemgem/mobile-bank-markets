# Paired development comparison: keep the original scores frozen.
args<-commandArgs(trailingOnly=TRUE)
work<-if(length(args)) args[1] else 'local-shrinkage-revised'
original<-if(length(args)>1) args[2] else 'local-shrinkage-validation'
cfg<-readRDS(file.path(work,'manifest.rds'))$config
old<-read.csv(file.path(original,'scores.csv'));new<-read.csv(file.path(work,'scores.csv'))
folds<-read.csv(file.path(work,'folds.csv'));old_folds<-read.csv(file.path(original,'folds.csv'))
stopifnot(identical(folds,old_folds))
paired<-merge(old,new,by=c('network_id','fold','regime','metric'),suffixes=c('_old','_new'))
stopifnot(all(abs(paired$observed_old-paired$observed_new)<1e-10))
write.csv(paired,file.path(work,'paired_scores.csv'),row.names=FALSE)
summarize<-function(scores,version) {
  groups<-unique(scores[c('regime','metric')])
  do.call(rbind,lapply(seq_len(nrow(groups)),function(i) {
    d<-scores[scores$regime==groups$regime[i] & scores$metric==groups$metric[i],]
    data.frame(version=version,regime=groups$regime[i],metric=groups$metric[i],
      n=nrow(d),mae=mean(d$absolute_error),crps=mean(d$crps),coverage=mean(d$covered),
      width=mean(d$width),min_draws=min(d$n_draws),max_draws=max(d$n_draws),
      planned_draws=max(d$expected_draws),complete=nrow(d)==nrow(folds) && all(d$n_draws==d$expected_draws))
  }))
}
summary<-rbind(summarize(old,'original'),summarize(new,'revised'))
write.csv(summary,file.path(work,'summary_comparison.csv'),row.names=FALSE)
fold_summary<-rbind(transform(aggregate(cbind(absolute_error,crps,covered,width)~fold+regime+metric,old,mean),version='original'),
  transform(aggregate(cbind(absolute_error,crps,covered,width)~fold+regime+metric,new,mean),version='revised'))
write.csv(fold_summary,file.path(work,'fold_comparison.csv'),row.names=FALSE)
audit<-read.csv(file.path(work,'bootstrap_audit.csv'))
laws<-list();leakage<-TRUE;resamples_identical<-TRUE;prediction_ok<-TRUE
for(fold in seq_len(cfg$folds)) {
  root<-file.path(work,sprintf('fold-%02d',fold));membership<-readRDS(file.path(root,'membership.rds'))
  leakage<-leakage && !length(intersect(membership$train,membership$test)) &&
    setequal(membership$test,folds$network_id[folds$fold==fold])
  for(b in 0:cfg$bootstrap_replicates) {
    label<-if(b==0) 'point' else sprintf('bootstrap-%02d',b)
    path<-file.path(root,label,'new_density_checkpoint.rds')
    checkpoint<-if(file.exists(path)) readRDS(path) else list(ok=FALSE,error='not attempted after failed preceding stage')
    if(checkpoint$ok) {
      law<-checkpoint$value
      laws[[length(laws)+1L]]<-data.frame(fold=fold,replicate=label,shift=law$shift,scale=law$scale,
        tau=law$tau,effective_sd=law$scale*law$tau,training_crps=law$training_crps,
        raw_training_crps=law$raw_training_crps,method=law$method,
        boundary=abs(law$shift)>=cfg$calibration_shift_bound-1e-5 || law$scale<1e-5 ||
          law$scale>=cfg$calibration_scale_bound-1e-5)
    } else laws[[length(laws)+1L]]<-data.frame(fold=fold,replicate=label,shift=NA_real_,scale=NA_real_,
      tau=NA_real_,effective_sd=NA_real_,training_crps=NA_real_,raw_training_crps=NA_real_,
      method=checkpoint$error,boundary=NA)
    if(b>0) {
      sample<-read.csv(file.path(root,label,'resample.csv'))
      prior<-read.csv(file.path(original,sprintf('fold-%02d',fold),label,'resample.csv'))
      resamples_identical<-resamples_identical && identical(sample,prior)
      leakage<-leakage && all(sample$source_id %in% membership$train) &&
        !any(sample$source_id %in% membership$test)
    }
  }
  for(regime in cfg$regimes) {
    path<-file.path(root,regime,'prediction_checkpoint.rds')
    prediction_ok<-prediction_ok && file.exists(path) && readRDS(path)$ok
  }
}
laws<-do.call(rbind,laws);write.csv(laws,file.path(work,'density_calibration_audit.csv'),row.names=FALSE)
lookup<-function(version,regime,metric,column) {
  result<-summary[summary$version==version & summary$regime==regime & summary$metric==metric,column]
  stopifnot(length(result)==1);result
}
complete<-all(summary[summary$version=='revised','complete']) &&
  nrow(audit)==cfg$folds*cfg$bootstrap_replicates && all(audit$admitted) && prediction_ok
coverage<-function(regime) vapply(c('n_links','degree_sd','n_isolates','largest_component','clustering'),
  function(metric) lookup('revised',regime,metric,'coverage'),numeric(1))
conditional_gain<-vapply(c('n_links','largest_component'),function(metric)
  1-lookup('revised','calibrated_uncertain',metric,'mae')/lookup('original','pooled_baseline',metric,'mae'),numeric(1))
conditional_pass<-complete && leakage && all(conditional_gain>=cfg$min_relative_improvement) &&
  all(coverage('calibrated_uncertain')>=cfg$min_predictive_coverage) &&
  lookup('revised','calibrated_uncertain','clustering','crps')<=lookup('original','pooled_baseline','clustering','crps')
new_pass<-complete && leakage && all(coverage('new_market_uncertain')>=cfg$min_predictive_coverage) &&
  all(vapply(c('n_links','largest_component','clustering'),function(metric)
    lookup('revised','new_market_uncertain',metric,'crps')<=lookup('original','pooled_baseline',metric,'crps'),logical(1)))
readiness<-data.frame(check=c('complete_fit_and_prediction_audit','training_test_separation',
  'identical_folds_and_bootstrap_samples','density_informed_pilot_screen','size_only_new_market_pilot_screen'),
  passed=c(complete,leakage,resamples_identical,conditional_pass,new_pass))
write.csv(readiness,file.path(work,'readiness.csv'),row.names=FALSE)
misses<-new[new$regime=='calibrated_uncertain' & new$metric=='degree_sd' & !new$covered,]
write.csv(misses[order(misses$absolute_error,decreasing=TRUE),],file.path(work,'degree_spread_misses.csv'),row.names=FALSE)
cat('READINESS\n');print(readiness,row.names=FALSE)
cat('\nKEY SCORES\n');print(summary[summary$regime %in% c('calibrated_uncertain','new_market_uncertain','new_market_raw') &
  summary$metric %in% c('n_links','degree_sd','largest_component','clustering'),],row.names=FALSE)
cat('\nDENSITY CALIBRATION\n');print(laws,row.names=FALSE)

png(file.path(work,'comparison.png'),width=2200,height=1120,res=160)
par(mfrow=c(2,4),mar=c(4,4,3,1),oma=c(2,0,2,0),bg='#f5f7fa',col.axis='#334155',col.lab='#334155')
for(regime in c('calibrated_uncertain','new_market_uncertain')) for(metric in c('n_links','degree_sd','largest_component','clustering')) {
  a<-old[old$regime==regime & old$metric==metric,];b<-new[new$regime==regime & new$metric==metric,]
  maximum<-if(metric=='clustering') 1 else max(a$observed,a$mean,b$mean)
  label<-c(n_links='Ties',degree_sd='Degree SD',largest_component='Largest component',clustering='Clustering')[[metric]]
  name<-if(regime=='calibrated_uncertain') 'Size + count supplied' else 'Size only'
  plot(a$observed,a$mean,xlim=c(0,maximum*1.05),ylim=c(0,maximum*1.05),pch=1,
    col=adjustcolor('#8758a6',.55),xlab='Held-out observed',ylab='Predictive mean',main=paste(name,label,sep=': '))
  points(b$observed,b$mean,pch=19,col=adjustcolor('#177b60',.65))
  abline(0,1,lty=2,col='#64748b')
}
mtext('Revised development pilot: original (purple open) vs revised (green filled)',outer=TRUE,cex=1.2)
mtext('Same folds and resamples; all fitted and predictive-calibration stages exclude the corresponding test markets.',
      side=1,outer=TRUE,cex=.9)
dev.off()

text<-c('# Revised degree/hub and new-market density pilot','',
  if(!complete) '**The revised uncertainty ensemble is incomplete. Scores below are provisional diagnostics, not evidence of validated improvement; see the full failure and replicate-count audit.**' else
    'All planned refits and predictions completed; scores remain development-pilot evidence rather than confirmatory validation.', '',
  'The revised model adds a fixed-decay-2 GW degree term alongside the original decay-0.5 term and GWESP closure. It also recalibrates the size-only new-market effect mean and scale using ERGM count simulations and training-only CRPS. Conditional size-plus-count prediction retains the original count-stage posterior effect distribution.', '',
  sprintf('The comparison uses the same %d folds, %d training-market bootstrap refits per fold, and %d graph predictions per test market/regime. All original results are preserved. Folds and bootstrap compositions matched: %s.',
    cfg$folds,cfg$bootstrap_replicates,cfg$bootstrap_replicates*cfg$effect_draws*cfg$graphs_per_effect,resamples_identical), '',
  '**This is development cross-validation, not fresh confirmatory validation.** Earlier outer-fold diagnostics informed the revision. Individual fitting and predictive-calibration stages still exclude their held-out markets, but repeated method development on the same data can make apparent improvement optimistic.', '',
  '## Paired held-out results','',
  'Lower MAE and CRPS are better. Coverage and width describe central 95% predictive ranges; broader intervals are not automatically better. Scores average over markets, not over independent graph replicates.', '',
  '| Protocol | Metric | Original MAE | Revised MAE | Original CRPS | Revised CRPS | Original coverage | Revised coverage |',
  '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |')
for(regime in c('calibrated_uncertain','new_market_uncertain')) for(metric in c('n_links','degree_sd','n_isolates','largest_component','clustering','triangles')) {
  text<-c(text,sprintf('| %s | %s | %.3f | %.3f | %.3f | %.3f | %.0f%% | %.0f%% |',regime,metric,
    lookup('original',regime,metric,'mae'),lookup('revised',regime,metric,'mae'),
    lookup('original',regime,metric,'crps'),lookup('revised',regime,metric,'crps'),
    100*lookup('original',regime,metric,'coverage'),100*lookup('revised',regime,metric,'coverage')))
}
text<-c(text,'','![Development comparison](comparison.png)','','## Density recalibration ablation','',
  'new_market_raw uses the revised degree specification but the old uncorrected effect law. It uses the same parameter/effect/graph seeds as corrected new-market prediction. This separates the contribution of predictive recalibration from the structural revision.', '',
  '| Metric | Revised raw CRPS | Revised recalibrated CRPS | Raw range width | Recalibrated width |',
  '| --- | ---: | ---: | ---: | ---: |')
for(metric in c('n_links','degree_sd','largest_component','clustering'))
  text<-c(text,sprintf('| %s | %.3f | %.3f | %.3f | %.3f |',metric,
    lookup('revised','new_market_raw',metric,'crps'),lookup('revised','new_market_uncertain',metric,'crps'),
    lookup('revised','new_market_raw',metric,'width'),lookup('revised','new_market_uncertain',metric,'width')))
text<-c(text,'','## Pilot screens and limitations','',
  paste0('- Complete fit and prediction audit: ',complete),
  paste0('- No training/test overlap in fits or calibration inputs: ',leakage),
  paste0('- Density-informed screen: ',conditional_pass),paste0('- Size-only new-market screen: ',new_pass),'',
  sprintf('Revised conditional degree-spread coverage was %.0f%%; %d markets were outside the predictive ranges, %d above the upper bound.',
    100*lookup('revised','calibrated_uncertain','degree_sd','coverage'),nrow(misses),sum(misses$observed>misses$q975)), '',
  'The original screening rules are retained: all stages complete; at least 25% tie/component MAE improvement for conditional generation; 85% minimum coverage on selected metrics; and proper-score checks against the original pooled baseline. These are declared pilot thresholds, not scientific certification. Inspect CRPS and errors, not only binary pass labels. summary_comparison.csv records minimum/maximum actual and planned draws; rejected bootstrap fits are not replaced, and partial mixtures cannot establish full uncertainty calibration.', '',
  'The model remains a two-stage empirical-Bayes approximation. Bootstrap draws preserve joint parameter dependence and refit predictive calibration, but there are only six parameter draws per fold. The simulated count-kernel interpolation, quadrature, and finite Monte Carlo calibration introduce additional numerical approximation. Conditional and new-market protocols are not claimed to form an exact Bayesian prior/posterior pair.', '',
  'Recheck component, clustering, and hub patterns as well as count scores. More accurate size-only density prediction does not guarantee correct liquidity-sharing pathways. Scope is the observed size range; larger or different markets require separate assessment. Production claims require more stable uncertainty estimation and confirmation outside this development comparison.', '',
  'No production graph library, public report, or large ABM experiment was generated. Data-derived outputs remain ignored. The source/config snapshot for the old run is under its source-v1 directory.', '',
  'Detailed artifacts: summary_comparison.csv, paired_scores.csv, fold_comparison.csv, density_calibration_audit.csv, degree_spread_misses.csv, and readiness.csv. See the [revised pipeline guide](../experiments/REVISED_SHRINKAGE.md).')
writeLines(text,file.path(work,'comparison.md'))
