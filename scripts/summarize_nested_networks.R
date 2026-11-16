args<-commandArgs(trailingOnly=TRUE)
work<-if(length(args)) args[1] else 'local-nested-validation'
for(h in c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R',
  'shrinkage_mutual_ergm_functions.R','validate_shrinkage_functions.R','activity_ergm_functions.R',
  'forecast_activity_functions.R','nested_network_functions.R')) source(file.path('scripts',h))
manifest<-readRDS(file.path(work,'manifest.rds'));cfg<-manifest$config
stopifnot(identical(manifest$code,tools::md5sum(names(manifest$code))))
stopifnot(identical(manifest$inputs,tools::md5sum(names(manifest$inputs))))
plan<-readRDS(file.path(work,'split_plan.rds'));scores<-choices<-audit<-list()
warning_rows<-list()
record_warnings<-function(folder,f,stage,result) {
  messages<-unique(c(result$value$warnings,readRDS(file.path(folder,'density.rds'))$warnings))
  data.frame(outer_fold=rep(f,length(messages)),stage=rep(stage,length(messages)),message=messages)
}
for(f in seq_len(cfg$outer_folds)) {
  root<-file.path(work,sprintf('outer-%02d',f));member<-readRDS(file.path(root,'membership.rds'))
  stopifnot(identical(member,plan$splits[[f]]))
  scores[[f]]<-read.csv(file.path(root,'test','outer_scores.csv'))
  choices[[f]]<-read.csv(file.path(root,'inner_selection.csv'))
  stopifnot(setequal(unique(scores[[f]]$network_id),member$test))
  for(i in seq_len(cfg$inner_folds)) {
    folder<-file.path(root,sprintf('inner-%02d',i))
    inner<-readRDS(file.path(folder,'membership.rds'))
    stopifnot(!length(intersect(inner$train,inner$validation)),
      setequal(c(inner$train,inner$validation),member$train),
      !length(intersect(c(inner$train,inner$validation),member$test)))
    path<-file.path(folder,'fit');result<-readRDS(file.path(path,'pair_checkpoint.rds'))
    stopifnot(result$ok)
    warning_rows[[length(warning_rows)+1L]]<-record_warnings(path,f,paste0('inner-',i),result)
    audit[[length(audit)+1L]]<-data.frame(outer_fold=f,stage=paste0('inner-',i),
      n_train=length(inner$train),distinct_sources=length(inner$train),
      elapsed_seconds=result$elapsed_seconds,pooled_status=readRDS(file.path(path,'pooled_result.rds'))$status,
      shared_status=readRDS(file.path(path,'shared_result.rds'))$status,
      tau=result$value$hub$tau,n_warnings=length(result$value$warnings))
  }
  for(b in seq_len(cfg$outer_bootstraps)) {
    folder<-file.path(root,sprintf('bootstrap-%02d',b))
    resample<-read.csv(file.path(folder,'resample.csv'))
    stopifnot(all(resample$source_id %in% member$train),!any(resample$source_id %in% member$test),
      nrow(resample)==length(member$train))
    result<-readRDS(file.path(folder,'pair_checkpoint.rds'));stopifnot(result$ok)
    warning_rows[[length(warning_rows)+1L]]<-record_warnings(folder,f,paste0('bootstrap-',b),result)
    audit[[length(audit)+1L]]<-data.frame(outer_fold=f,stage=paste0('bootstrap-',b),
      n_train=nrow(resample),distinct_sources=length(unique(resample$source_id)),
      elapsed_seconds=result$elapsed_seconds,pooled_status=readRDS(file.path(folder,'pooled_result.rds'))$status,
      shared_status=readRDS(file.path(folder,'shared_result.rds'))$status,
      tau=result$value$hub$tau,n_warnings=length(result$value$warnings))
  }
}
scores<-do.call(rbind,scores);choices<-do.call(rbind,choices);audit<-do.call(rbind,audit)
stopifnot(nrow(audit)==cfg$outer_folds*(cfg$inner_folds+cfg$outer_bootstraps),
  all(audit$pooled_status=='ready_for_review'),all(audit$shared_status=='ready_for_review'),
  length(unique(scores$network_id))==nrow(plan$outer),all(table(scores$network_id,scores$regime)==length(cfg$metrics)),
  all(scores$n_draws==cfg$outer_bootstraps*cfg$outer_effects*cfg$graphs_per_effect))
write.csv(scores,file.path(work,'outer_scores.csv'),row.names=FALSE)
write.csv(choices,file.path(work,'inner_selections.csv'),row.names=FALSE)
write.csv(audit,file.path(work,'fit_audit.csv'),row.names=FALSE)
warnings<-do.call(rbind,warning_rows)
warnings$encoding_message<-grepl('native encoding|translated to UTF-8',warnings$message)
warnings$solver_fallback<-grepl("Rglpk.*not available; falling back to 'lpSolveAPI'",warnings$message)
write.csv(warnings,file.path(work,'fit_warnings.csv'),row.names=FALSE)
misses<-scores[scores$metric %in% c('degree_sd','max_degree') & !scores$covered,]
misses$direction<-ifelse(misses$observed>misses$q975,'above','below')
write.csv(misses,file.path(work,'hub_interval_misses.csv'),row.names=FALSE)
summary<-aggregate(cbind(crps,empirical_crps,absolute_error,covered,width,scaled_crps)~regime+metric,scores,mean)
fold_summary<-aggregate(cbind(crps,absolute_error,covered,width,scaled_crps)~regime+metric+outer_fold,scores,mean)
write.csv(summary,file.path(work,'outer_summary.csv'),row.names=FALSE)
write.csv(fold_summary,file.path(work,'fold_summary.csv'),row.names=FALSE)
composite<-nested_composite(scores,cfg)
composite<-merge(composite,plan$outer[c('network_id','fold')],by='network_id')
a<-composite[composite$regime=='pooled',c('network_id','fold','scaled_crps')]
b<-composite[composite$regime=='corrected_hub',c('network_id','fold','scaled_crps')]
paired<-merge(a,b,by=c('network_id','fold'),suffixes=c('_pooled','_hub'))
paired$difference<-paired$scaled_crps_hub-paired$scaled_crps_pooled
paired$selected<-choices$selected[match(paired$fold,choices$outer_fold)]
paired$selected_score<-ifelse(paired$selected=='pooled',paired$scaled_crps_pooled,paired$scaled_crps_hub)
write.csv(paired,file.path(work,'paired_composites.csv'),row.names=FALSE)
set.seed(cfg$nested_seed+999999L)
groups<-split(seq_len(nrow(paired)),paired$fold)
boot<-replicate(cfg$report_bootstraps,{
  indices<-unlist(lapply(groups,function(index) sample(index,length(index),replace=TRUE)))
  mean(paired$difference[indices])
})
difference<-mean(paired$difference);se<-sd(paired$difference)/sqrt(nrow(paired))
interval<-quantile(boot,c(.025,.975),names=FALSE)
hub_coverage<-summary$covered[summary$regime=='corrected_hub' & summary$metric %in% cfg$selection_metrics]
votes<-sum(choices$selected=='corrected_hub')
recommendation<-if(votes>=ceiling(cfg$outer_folds/2) && difference+se<0 &&
  all(hub_coverage>=cfg$min_predictive_coverage)) 'corrected_hub' else 'pooled'
decision<-data.frame(recommended=recommendation,hub_inner_votes=votes,total_outer_folds=cfg$outer_folds,
  pooled_composite=mean(paired$scaled_crps_pooled),hub_composite=mean(paired$scaled_crps_hub),
  nested_selected_composite=mean(paired$selected_score),difference=difference,paired_se=se,
  case_bootstrap_q025=interval[1],case_bootstrap_q975=interval[2],
  hub_coverage_floor_pass=all(hub_coverage>=cfg$min_predictive_coverage),
  minimum_tested_size=min(plan$outer$n_nodes),maximum_tested_size=max(plan$outer$n_nodes))
write.csv(decision,file.path(work,'recommendation.csv'),row.names=FALSE)
performance<-do.call(rbind,lapply(seq_len(cfg$outer_folds),function(f)
  do.call(rbind,lapply(c('pooled','hub'),function(model) {
    x<-readRDS(file.path(work,sprintf('outer-%02d',f),'test',model,'prediction_checkpoint.rds'))
    data.frame(outer_fold=f,model=model,graphs=nrow(x$value),seconds=x$elapsed_seconds,
      graphs_per_second=nrow(x$value)/x$elapsed_seconds)
  }))))
write.csv(performance,file.path(work,'generation_performance.csv'),row.names=FALSE)
png(file.path(work,'comparison.png'),width=1500,height=1100,res=150)
par(mfrow=c(2,2),mar=c(4,5,3,1),oma=c(2,0,3,0),bg='#f5f7fa',col.axis='#334155',col.lab='#334155')
colors<-c('#177b60','#2563eb','#b65b2a')
limit<-max(paired$scaled_crps_pooled,paired$scaled_crps_hub)*1.05
plot(paired$scaled_crps_pooled,paired$scaled_crps_hub,pch=19,col=adjustcolor(colors[paired$fold],.6),
  xlim=c(0,limit),ylim=c(0,limit),xlab='Pooled composite score',ylab='Corrected hub composite score',
  main='Outer held-out market scores');abline(0,1,lty=2,col='#64748b')
legend('topleft',legend=paste('Outer fold',1:cfg$outer_folds),pch=19,col=colors,bty='n',cex=.8)
metrics<-cfg$selection_metrics;ratio<-vapply(metrics,function(m)
  summary$crps[summary$regime=='corrected_hub' & summary$metric==m]/
    summary$crps[summary$regime=='pooled' & summary$metric==m],numeric(1))
labels<-c(n_links='Ties',degree_sd='Degree SD',max_degree='Max degree',n_isolates='Isolates',
  largest_component='Largest comp.',clustering='Clustering')
plot(ratio,seq_along(ratio),yaxt='n',pch=19,xlim=range(c(.9,1.1,ratio)),
  xlab='Hub / pooled CRPS (below 1 favors hubs)',ylab='',main='Marginal predictive scores')
axis(2,at=seq_along(metrics),labels=labels[metrics],las=1,cex.axis=.75);abline(v=1,lty=2,col='#64748b')
fold_composite<-aggregate(cbind(scaled_crps_pooled,scaled_crps_hub,selected_score)~fold,paired,mean)
matplot(fold_composite$fold,fold_composite[c('scaled_crps_pooled','scaled_crps_hub','selected_score')],
  type='b',pch=c(16,17,15),lty=c(1,1,2),col=c('#2563eb','#177b60','#334155'),
  xlab='Outer fold',ylab='Mean composite CRPS',main='Fold variation and selected pipeline',xaxt='n')
axis(1,at=1:cfg$outer_folds);legend('topright',c('Pooled','Corrected hub','Inner-selected'),
  col=c('#2563eb','#177b60','#334155'),pch=c(16,17,15),lty=c(1,1,2),bty='n',cex=.75)
coverage<-sapply(c('pooled','corrected_hub'),function(r) vapply(metrics,function(m)
  summary$covered[summary$regime==r & summary$metric==m],numeric(1)))
plot(coverage[,1],seq_along(metrics)-.08,xlim=c(min(.7,coverage),1.03),ylim=c(.8,length(metrics)+.2),
  yaxt='n',pch=16,col='#2563eb',xlab='Central 95% predictive coverage',ylab='',main='Marginal coverage')
points(coverage[,2],seq_along(metrics)+.08,pch=17,col='#177b60')
axis(2,at=seq_along(metrics),labels=labels[metrics],las=1,cex.axis=.75)
abline(v=c(.85,.95),lty=c(3,2),col='#64748b')
legend('bottomleft',c('Pooled','Corrected hub'),pch=c(16,17),col=c('#2563eb','#177b60'),bty='n',cex=.75)
mtext('Nested internal validation: new markets known only by kiosk count',outer=TRUE,cex=1.15)
mtext('Three outer folds; two inner folds; matched bootstrap ensembles. Prior development used these markets.',
  outer=TRUE,side=1,cex=.85);dev.off()
metric_score<-function(r,m,column='crps') summary[summary$regime==r & summary$metric==m,column]
lines<-c('# Nested validation: pooled versus corrected hub generator','',
  sprintf('Recommendation for size-only new-market generation: **%s**. All %d training fit pairs completed, covering %d held-out outer markets. Every outer candidate used %d graphs per market from %d matched parameter bootstraps.',
    recommendation,nrow(audit),nrow(paired),cfg$outer_bootstraps*cfg$outer_effects*cfg$graphs_per_effect,cfg$outer_bootstraps),'',
  '## Primary result','',
  '| Generator | Mean normalized composite CRPS |','| --- | ---: |',
  sprintf('| Pooled | %.4f |',decision$pooled_composite),
  sprintf('| Corrected hub | %.4f |',decision$hub_composite),
  sprintf('| Inner-selected pipeline | %.4f |',decision$nested_selected_composite),'',
  sprintf('Paired corrected-hub minus pooled difference: %.4f; paired SE %.4f. Conditional case-bootstrap 95%% interval: [%.4f, %.4f]. Negative favors hubs. Relative composite change: %+.1f%%.',
    difference,se,interval[1],interval[2],100*(decision$hub_composite/decision$pooled_composite-1)),'',
  sprintf('Inner selections chose corrected hubs in %d of %d outer folds. The predeclared rule recommends hubs only with a majority of inner votes, an outer composite gain exceeding one paired SE, and at least 85%% coverage on all six selection features. Hub coverage-floor check: %s.',
    votes,cfg$outer_folds,decision$hub_coverage_floor_pass),'',
  '## Outer marginal fit','',
  '| Feature | Pooled CRPS | Hub CRPS | Pooled coverage | Hub coverage |',
  '| --- | ---: | ---: | ---: | ---: |')
for(m in cfg$metrics) lines<-c(lines,sprintf('| %s | %.3f | %.3f | %.0f%% | %.0f%% |',m,
  metric_score('pooled',m),metric_score('corrected_hub',m),100*metric_score('pooled',m,'covered'),100*metric_score('corrected_hub',m,'covered')))
lines<-c(lines,'','## Inner selections','',
  '| Outer fold | Inner choice | Hub-minus-pooled inner difference | Paired SE |',
  '| --- | --- | ---: | ---: |')
for(i in seq_len(nrow(choices))) {x<-choices[i,];lines<-c(lines,sprintf('| %d | %s | %.4f | %.4f |',
  x$outer_fold,x$selected,x$inner_difference,x$inner_se))}
lines<-c(lines,'','## Interpretation for the ABM','',
  if(recommendation=='pooled')
    'Use the pooled structural ERGM as the primary generator for new-market ABM networks under the tested size-only protocol. The corrected hub family has not earned replacement under the predeclared conservative rule. Retain it as a structural sensitivity alternative if hub concentration is consequential for liquidity sharing.' else
    'Use the corrected hub family as the primary new-market structural generator under the tested size-only protocol; retain pooled networks as a simpler sensitivity baseline. Preserve the calibrated activity and closure mixtures and count-law uncertainty when producing its ensemble.', '',
  sprintf('Refit the chosen pipeline on all available markets before generating a production library, retain multiple independent networks per scenario, and record seeds and realized statistics. Initial empirically based ensembles should stay within the tested size range of %d–%d kiosks; larger graphs are explicit structural extrapolations. This run does not export a library. A supplied size-and-tie-count experiment conditions away density uncertainty and needs its own topology comparison; the present recommendation does not claim to settle that case.',min(plan$outer$n_nodes),max(plan$outer$n_nodes)),'',
  '## What makes this nested','',
  'Outer test markets never enter fitting, calibration, normalization, inner family selection, or a training bootstrap. Their kiosk counts alone enter graph prediction; their topology and tie count are joined only for scoring. Inner splits independently choose the family using the fixed six-feature composite and one-SE simplicity preference. The selected pipeline is then scored on the untouched outer test partition. Model-specific outer scores also support the practical generator recommendation, which is itself not an independent test of a final fixed winner.','',
  'Both models use the same three bootstrap resamples in each outer fold, and both use the same graph/effect budget. All stages of each family are refitted. The ordinary empirical CRPS and the independent-group corrected CRPS are retained; selection uses the latter to avoid favoring a model merely because its graphs share more latent randomness.','',
  '## Limits','',
  'These markets informed earlier development. Nested splits control selection in this run but do not create fresh external validation. Three outer folds, two inner folds, and three parameter bootstraps are a bounded internal comparison; tail uncertainty and split sensitivity remain. The market-bootstrap interval is conditional on the fitted folds and does not fully capture their shared training dependence. The one-SE decision rules are heuristics, not significance or noninferiority tests.','',
  'The recommendation concerns synthetic undirected mutual stated willingness-to-trade networks, including isolates. It does not certify customer demand assumptions, operator behavior, or simulated economic outcomes. Coverage should be read against nominal 95%, as well as the less demanding 85% pilot floor.','',
  'Earlier pilot tables used different splits, uncertainty budgets, and ordinary empirical CRPS; their numerical values are not directly comparable to this matched, independently grouped comparison.','',
  '![Nested comparison](comparison.png)','',
  'All original pilot results remain unchanged. All new data-derived outputs are ignored and private; nothing was published. See [design and commands](../experiments/NESTED_NETWORK_VALIDATION.md).')
lines<-c(lines,'',if(all(warnings$encoding_message | warnings$solver_fallback))
  'Recorded fit warnings concerned native-encoding translation and use of the installed lpSolveAPI solver when optional Rglpk was unavailable. All fit-status screens passed; the messages and timings remain in fit_warnings.csv, fit_audit.csv, and worker logs.' else
  'Fit warnings include messages beyond native-encoding translation. Inspect fit_warnings.csv and fit_audit.csv alongside model diagnostics before generation.')
lines<-c(lines,'',sprintf('Pooled maximum-degree intervals missed %d observed hubs above their upper bound, versus %d for corrected hubs. This is a concrete reason to keep the hub family as an ABM structural sensitivity alternative despite choosing the simpler primary generator. See hub_interval_misses.csv.',
  sum(misses$regime=='pooled' & misses$metric=='max_degree' & misses$direction=='above'),
  sum(misses$regime=='corrected_hub' & misses$metric=='max_degree' & misses$direction=='above')))
timing<-aggregate(cbind(graphs,seconds)~model,performance,sum)
lines<-c(lines,'','## Observed validation runtime','',
  'These times include graph generation and calculation of validation summaries, excluding fitting and CSV export. They are measured timings for this machine and small-market domain, not a large-study runtime guarantee.','',
  '| Generator | Outer graphs | Worker seconds | Graph summaries per second |',
  '| --- | ---: | ---: | ---: |')
for(i in seq_len(nrow(timing))) {x<-timing[i,];lines<-c(lines,sprintf('| %s | %d | %.1f | %.1f |',
  x$model,x$graphs,x$seconds,x$graphs/x$seconds))}
writeLines(lines,file.path(work,'comparison.md'))
saveRDS(list(code=tools::md5sum('scripts/summarize_nested_networks.R'),
  inputs=tools::md5sum(c(file.path(work,'manifest.rds'),file.path(work,'split_plan.rds'),
    file.path(work,sprintf('outer-%02d',seq_len(cfg$outer_folds)),'test','outer_scores.csv'),
    file.path(work,sprintf('outer-%02d',seq_len(cfg$outer_folds)),'inner_selection.csv')))),
  file.path(work,'comparison_manifest.rds'))
print(decision,row.names=FALSE);print(summary[c('regime','metric','crps','covered')],row.names=FALSE)
