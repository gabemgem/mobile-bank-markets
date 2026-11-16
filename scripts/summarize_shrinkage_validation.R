# Descriptive held-out scores and explicit pilot screening, with no data publication.
args<-commandArgs(trailingOnly=TRUE)
work<-if(length(args)) args[1] else 'local-shrinkage-validation'
manifest<-readRDS(file.path(work,'manifest.rds'));cfg<-manifest$config
scores<-read.csv(file.path(work,'scores.csv'))
folds<-read.csv(file.path(work,'folds.csv'))
audit<-read.csv(file.path(work,'bootstrap_audit.csv'))
regimes<-c('pooled_baseline','calibrated_plugin','calibrated_uncertain','new_market_uncertain')
metrics<-unique(scores$metric)
summary<-do.call(rbind,lapply(regimes,function(regime) do.call(rbind,lapply(metrics,function(metric) {
  d<-scores[scores$regime==regime & scores$metric==metric,]
  data.frame(regime=regime,metric=metric,n_markets=nrow(d),mae=mean(d$absolute_error),
    crps=mean(d$crps),coverage=mean(d$covered),mean_width=mean(d$width),
    complete=all(d$n_draws==d$expected_draws) && nrow(d)==nrow(folds))
}))))
write.csv(summary,file.path(work,'summary.csv'),row.names=FALSE)
fold_summary<-aggregate(cbind(absolute_error,crps,covered,width)~fold+regime+metric,scores,mean)
write.csv(fold_summary,file.path(work,'fold_summary.csv'),row.names=FALSE)
leakage_ok<-TRUE;prediction_ok<-TRUE;timing<-list();variances<-list()
for(fold in seq_len(cfg$folds)) {
  root<-file.path(work,sprintf('fold-%02d',fold))
  membership<-readRDS(file.path(root,'membership.rds'))
  leakage_ok<-leakage_ok && !length(intersect(membership$train,membership$test)) &&
    setequal(membership$test,folds$network_id[folds$fold==fold])
  for(b in seq_len(cfg$bootstrap_replicates)) {
    resample<-read.csv(file.path(root,sprintf('bootstrap-%02d',b),'resample.csv'))
    leakage_ok<-leakage_ok && all(resample$source_id %in% membership$train) &&
      !any(resample$source_id %in% membership$test)
  }
  for(regime in regimes) {
    path<-file.path(root,regime,'prediction_checkpoint.rds')
    if(!file.exists(path)) {prediction_ok<-FALSE;next}
    r<-readRDS(path);prediction_ok<-prediction_ok && r$ok
    if(!r$ok) next
    p<-r$value
    if(regime %in% c('calibrated_uncertain','new_market_uncertain')) for(id in unique(p$network_id))
      for(metric in c('n_links','largest_component','clustering')) {
        d<-p[p$network_id==id,];x<-d[[metric]]
        param<-ave(x,d$parameter_id,FUN=mean)
        effect<-ave(x,interaction(d$parameter_id,d$effect_id,drop=TRUE),FUN=mean)
        total<-mean((x-mean(x))^2)
        pieces<-c(parameter=mean((param-mean(x))^2),effect=mean((effect-param)^2),graph=mean((x-effect)^2))
        stopifnot(abs(sum(pieces)-total)<1e-7)
        variances[[length(variances)+1L]]<-data.frame(fold=fold,network_id=id,regime=regime,
          metric=metric,total=total,between_parameter=pieces[1],between_effect=pieces[2],within_graph=pieces[3])
      }
  }
}
if(length(variances)) write.csv(do.call(rbind,variances),file.path(work,'variance_decomposition.csv'),row.names=FALSE)
get<-function(regime,metric,column) summary[summary$regime==regime & summary$metric==metric,column]
complete<-nrow(audit)==cfg$folds*cfg$bootstrap_replicates && all(audit$admitted) &&
  all(summary$complete) && prediction_ok && leakage_ok
conditional_improvement<-vapply(c('n_links','largest_component'),function(metric)
  1-get('calibrated_uncertain',metric,'mae')/get('pooled_baseline',metric,'mae'),numeric(1))
conditional_coverage<-vapply(c('n_links','degree_sd','n_isolates','largest_component','clustering'),function(metric)
  get('calibrated_uncertain',metric,'coverage'),numeric(1))
new_coverage<-vapply(c('n_links','degree_sd','n_isolates','largest_component','clustering'),function(metric)
  get('new_market_uncertain',metric,'coverage'),numeric(1))
new_crps<-vapply(c('n_links','largest_component','clustering'),function(metric)
  get('new_market_uncertain',metric,'crps')<=get('pooled_baseline',metric,'crps'),logical(1))
conditional_pass<-complete && all(conditional_improvement>=cfg$min_relative_improvement) &&
  all(conditional_coverage>=cfg$min_predictive_coverage) &&
  get('calibrated_uncertain','clustering','crps')<=get('pooled_baseline','clustering','crps')
new_pass<-complete && all(new_coverage>=cfg$min_predictive_coverage) && all(new_crps)
readiness<-data.frame(check=c('complete_fit_and_prediction_audit','training_test_separation',
  'density_informed_pilot_screen','size_only_new_market_pilot_screen'),
  passed=c(complete,leakage_ok,conditional_pass,new_pass))
write.csv(readiness,file.path(work,'readiness.csv'),row.names=FALSE)
degree_misses<-scores[scores$regime=='calibrated_uncertain' & scores$metric=='degree_sd' & !scores$covered,]
degree_misses<-degree_misses[order(degree_misses$absolute_error,decreasing=TRUE),]
write.csv(degree_misses,file.path(work,'degree_spread_misses.csv'),row.names=FALSE)
cat('BOOTSTRAPS\n');print(audit,row.names=FALSE)
cat('\nSUMMARY\n');print(summary,row.names=FALSE)
cat('\nPILOT SCREENS\n');print(readiness,row.names=FALSE)
cat('\nBy-fold scores are in fold_summary.csv. Parameter draws per fold:',cfg$bootstrap_replicates,
    '; assess tail stability before production use.\n')

png(file.path(work,'validation.png'),width=2300,height=1120,res=160)
par(mfrow=c(2,4),mar=c(4,4,3,1),oma=c(2,0,2,0),bg='#f5f7fa',col.axis='#334155',col.lab='#334155')
colors<-c(calibrated_uncertain='#177b60',new_market_uncertain='#b65b2a')
for(regime in names(colors)) for(metric in c('n_links','degree_sd','largest_component','clustering')) {
  d<-scores[scores$regime==regime & scores$metric==metric,]
  both<-scores[scores$regime %in% names(colors) & scores$metric==metric,]
  maximum<-if(metric=='clustering') 1 else max(both$observed,both$mean)
  name<-if(regime=='calibrated_uncertain') 'Size + count supplied' else 'Size only'
  label<-c(n_links='Ties',degree_sd='Degree SD',largest_component='Largest component',clustering='Clustering')[[metric]]
  plot(d$observed,d$mean,xlim=c(0,maximum*1.05),ylim=c(0,maximum*1.05),
    col=adjustcolor(colors[regime],.6),pch=19,xlab='Held-out observed',ylab='Predictive mean',
    main=paste(name,label,sep=': '))
  abline(0,1,lty=2,col='#64748b')
}
mtext('Held-out markets with propagated uncertainty: conditional generation vs new-market prediction',outer=TRUE,cex=1.1)
mtext('All fitted stages exclude each test market. The upper row uses its count only for the declared density-calibration step.',
      side=1,outer=TRUE,cex=.85)
dev.off()

text<-c('# Density-shrinkage validation pilot','',
  sprintf('%d size-balanced folds hold out each of %d markets once. Every initializer, calibration, and ERGM fit uses training markets only. %d market-level bootstrap refits per fold jointly propagate calibration and structural-parameter variation; %d effect draws and %d graph draws per effect yield %d planned predictive graphs per market/regime.',
    cfg$folds,nrow(folds),cfg$bootstrap_replicates,cfg$effect_draws,cfg$graphs_per_effect,
    cfg$bootstrap_replicates*cfg$effect_draws*cfg$graphs_per_effect),
  '', '## Readiness finding','',
  if(!conditional_pass && !new_pass)
    '**Neither use case cleared all of the pilot screens. The pipeline is operational, but the model is not yet ready to be treated as a validated production generator.**'
  else '**Readiness differs by use case; passing a pilot screen supports exploratory use, not production certification.**', '',
  sprintf('%d of %d planned bootstrap refits were admitted. Data separation and prediction completeness checks passed: %s. No fit was silently substituted or excluded.',sum(audit$admitted),cfg$folds*cfg$bootstrap_replicates,complete), '',
  sprintf('With size and count supplied, held-out tie MAE was %.3f versus %.3f for the pooled baseline; largest-component MAE was %.3f versus %.3f. These gains validate conditional topology generation, not prediction of an unknown market density.',
    get('calibrated_uncertain','n_links','mae'),get('pooled_baseline','n_links','mae'),
    get('calibrated_uncertain','largest_component','mae'),get('pooled_baseline','largest_component','mae')), '',
  sprintf('The conditional degree-SD range covered %.0f%% of markets; the pilot screening floor is %.0f%% and the nominal range is 95%%. Coverage by fold is available below. Inspect the direction of misses: mean degree agreement or tie-count agreement does not guarantee faithful hub structure.',
    100*get('calibrated_uncertain','degree_sd','coverage'),100*cfg$min_predictive_coverage), '',
  sprintf('%d of the %d degree-spread misses were above the predictive upper bound. This points predominantly to underrepresented degree heterogeneity/hubs, rather than merely symmetric random error. Individual cases are saved in degree_spread_misses.csv.',
    sum(degree_misses$observed>degree_misses$q975),nrow(degree_misses)), '',
  sprintf('For size-only new markets, tie CRPS was %.3f versus baseline %.3f, and largest-component CRPS was %.3f versus %.3f (lower is better). Its tie coverage was %.0f%%, but mean predictive range width was %.2f ties versus %.2f for the baseline. More coverage by itself does not demonstrate improved prediction.',
    get('new_market_uncertain','n_links','crps'),get('pooled_baseline','n_links','crps'),
    get('new_market_uncertain','largest_component','crps'),get('pooled_baseline','largest_component','crps'),
    100*get('new_market_uncertain','n_links','coverage'),get('new_market_uncertain','n_links','mean_width'),
    get('pooled_baseline','n_links','mean_width')), '',
  'Retain the conditional model as the most promising exploratory candidate, while improving/validating degree and hub behavior before large ABM studies. Revisit the new-market density-effect distribution and its interaction with the structural ERGM before claiming generic new-market validity. Increasing bootstrap counts is needed for stable uncertainty estimates but will not by itself fix systematic structural bias.', '',
  'The count-supplied protocol already knows the observed tie count. Its tie score is therefore a conditional calibration diagnostic, not an independent test of density prediction. Worse scores after adding uncertainty are not grounds to hide uncertainty or return to unjustifiably fixed effects.',
  '', '## Held-out scores','',
  'Lower MAE and CRPS are better. Coverage is the fraction of held-out observations inside central 95% predictive ranges. Wider ranges are not automatically better; CRPS penalizes excessive dispersion. All metrics average over markets, not over independent graph replicates.', '',
  '| Regime | Metric | MAE | CRPS | Coverage | Mean range width |',
  '| --- | --- | ---: | ---: | ---: | ---: |')
for(i in seq_len(nrow(summary))) {
  d<-summary[i,]
  text<-c(text,sprintf('| %s | %s | %.3f | %.3f | %.0f%% | %.3f |',
    d$regime,d$metric,d$mae,d$crps,100*d$coverage,d$mean_width))
}
text<-c(text,'','![Validation plot](validation.png)','','## Pilot screening','',
  sprintf('These are transparent configured pilot checks, not scientific certification. All bootstrap and prediction stages must succeed with complete replicate counts. Density-informed generation must improve tie and largest-component MAE by at least %.0f%%, reach %.0f%% predictive coverage for the configured key metrics, and avoid worse clustering CRPS than the pooled baseline. Size-only prediction must meet that coverage screen and not worsen ties/component/clustering CRPS versus the baseline.',
    100*cfg$min_relative_improvement,100*cfg$min_predictive_coverage), '',
  paste0('- Complete fit/prediction audit: ',complete),
  paste0('- Training/test separation audit: ',leakage_ok),
  paste0('- Density-informed pilot screen: ',conditional_pass),
  paste0('- Size-only new-market pilot screen: ',new_pass),'',
  'Density-informed predictions use the held-out size and total tie count, but never its adjacency or structural features. They test conditional topology generation, not density prediction. Size-only predictions receive no held-out counts or topology; their uncertainty includes a new Gaussian market effect.', '',
  '## Limits and readiness interpretation','',
  'The generator remains a two-stage empirical-Bayes approximation. Market bootstraps preserve dependence within sampled training graphs and refit both stages. Parameter tuples are kept jointly; no extra Gaussian coefficient noise is added on top. Density-informed effect uncertainty is integrated from the binomial calibration posterior using a numerical grid. New-market effects are drawn from the bootstrap Gaussian distribution.', '',
  sprintf('This run uses %d bootstrap parameter draws per fold. Check stability of extreme quantiles and bootstrap covariance before production use. Prediction ranges omit model-class, survey, roster, and domain-shift uncertainty. Individual graph replicates and markets sharing parameter draws are dependent. Do not treat the %s planned diagnostic graphs as independent validation observations.',
    cfg$bootstrap_replicates,format(nrow(folds)*cfg$bootstrap_replicates*cfg$effect_draws*cfg$graphs_per_effect*length(regimes),big.mark=',',scientific=FALSE)), '',
  'The between-parameter, between-effect, and within-graph variance decomposition is empirical and includes Monte Carlo noise in the finite nested group means; its pieces sum exactly to the stored sample variance. It is not an exact theoretical allocation of all inferential uncertainty.', '',
  'Conditional and size-only readiness are separate. A passing conditional pilot can justify a small exploratory ABM ensemble with supplied density summaries, while failing size-only scores preclude claiming validation for arbitrary new markets. Neither passing screen alone certifies policy conclusions or authorizes publication of private inputs.', '',
  'Inspect fold_summary.csv for fold stability, bootstrap_audit.csv for all failures/boundary cases, readiness.csv for the checks, and scores.csv for per-market errors/ranges. Review remaining hubs, isolated components, and strongly clustered groups before a large ABM sensitivity study.', '',
  'No production library, public report, or ABM batch was generated. Inputs and data-derived outputs stay under ignored local directories. See the [pipeline guide](../experiments/VALIDATE_SHRINKAGE.md).')
writeLines(text,file.path(work,'comparison.md'))
