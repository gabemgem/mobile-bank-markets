# Reuse immutable, training-only original fits; recalibrate only new-market effects.
args<-commandArgs(trailingOnly=TRUE)
parent<-if(length(args)) args[1] else 'local-shrinkage-validation'
work<-if(length(args)>1) args[2] else 'local-density-recalibration'
packages<-c('ergm','ergm.multi','network','igraph','lme4','callr','coda')
for(package in packages) stopifnot(requireNamespace(package,quietly=TRUE))
helpers<-normalizePath(file.path('scripts',c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R',
  'shrinkage_mutual_ergm_functions.R','validate_shrinkage_functions.R','revised_shrinkage_functions.R')))
for(helper in helpers) source(helper)
cfg<-dget('experiments/configs/revised_shrinkage_validation.R');cfg$structural_terms<-NULL
source_manifest<-readRDS(file.path(parent,'manifest.rds'))
stopifnot(identical(source_manifest$inputs,unname(tools::md5sum(file.path('data',c('networks.csv','nodes.csv','edges.csv'))))))
for(key in c('split_seed','bootstrap_seed','bootstrap_replicates','effect_draws','graphs_per_effect'))
  stopifnot(identical(cfg[[key]],source_manifest$config[[key]]))
manifest<-list(config=cfg,parent_manifest=unname(tools::md5sum(file.path(parent,'manifest.rds'))),
  inputs=source_manifest$inputs,code=unname(tools::md5sum(c('scripts/validate_density_recalibration.R',helpers))),
  packages=vapply(packages,function(p) as.character(utils::packageVersion(p)),character(1)),R=R.version.string)
path<-file.path(work,'manifest.rds')
if(file.exists(path)) stopifnot(identical(manifest,readRDS(path))) else {
  if(dir.exists(work) && length(list.files(work,all.files=TRUE,no..=TRUE))) stop('Nonempty work directory without manifest.')
  dir.create(work,recursive=TRUE,showWarnings=FALSE);saveRDS(manifest,path)
}
nets<-read_mutual_library('data');folds<-read.csv(file.path(parent,'folds.csv'))
file.copy(file.path(parent,'folds.csv'),file.path(work,'folds.csv'),overwrite=TRUE)
stage<-function(fun,extra,folder,label,timeout=cfg$diagnostic_timeout) {
  dir.create(folder,recursive=TRUE,showWarnings=FALSE);path<-file.path(folder,paste0(label,'_checkpoint.rds'))
  if(file.exists(path)) return(readRDS(path))
  start<-proc.time()[['elapsed']]
  result<-tryCatch(list(ok=TRUE,value=callr::r(function(helpers,fun,extra) {
    for(helper in helpers) source(helper)
    do.call(get(fun),extra)
  },args=list(helpers=helpers,fun=fun,extra=extra),timeout=timeout,
    stdout=file.path(folder,paste0(label,'.log')),stderr=file.path(folder,paste0(label,'-errors.log'))),error=''),
    error=function(e) list(ok=FALSE,value=NULL,error=conditionMessage(e)))
  result$elapsed_seconds<-proc.time()[['elapsed']]-start;saveRDS(result,path)
  cat(label,if(result$ok) 'complete' else result$error,sprintf('(%.1f s)',result$elapsed_seconds),'\n')
  result
}
all_scores<-list();audit<-list()
for(fold in seq_len(cfg$folds)) {
  cat('Calibration-only fold',fold,'\n')
  source_root<-file.path(parent,sprintf('fold-%02d',fold))
  membership<-readRDS(file.path(source_root,'membership.rds'))
  root<-file.path(work,sprintf('fold-%02d',fold));dir.create(root,showWarnings=FALSE)
  saveRDS(membership,file.path(root,'membership.rds'))
  original_parameters<-readRDS(file.path(source_root,'parameter_draws.rds'))
  stopifnot(length(original_parameters)==cfg$bootstrap_replicates)
  parameters<-list()
  for(i in seq_along(original_parameters)) {
    parameter<-original_parameters[[i]]
    b<-as.integer(sub('bootstrap-','',parameter$id));label<-sprintf('bootstrap-%02d',b)
    sample<-read.csv(file.path(source_root,label,'resample.csv'))
    stopifnot(all(sample$source_id %in% membership$train),!any(sample$source_id %in% membership$test))
    boot<-nets[sample$source_id];names(boot)<-sample$resample_id
    folder<-file.path(root,label);dir.create(folder,showWarnings=FALSE)
    write.csv(sample,file.path(folder,'resample.csv'),row.names=FALSE)
    law<-stage('calibrate_new_market',list(nets=boot,beta=parameter$beta,tau=parameter$tau,
      cfg=cfg,seed=cfg$calibration_seed+fold*1000L+b),folder,'new_density')
    ok<-law$ok && law$value$convergence==0
    audit[[length(audit)+1L]]<-data.frame(fold=fold,bootstrap=b,admitted=ok,
      source_fit_md5=unname(tools::md5sum(file.path(source_root,label,'fit.rds'))),
      shift=if(ok) law$value$shift else NA_real_,scale=if(ok) law$value$scale else NA_real_,
      tau=parameter$tau,reason=if(law$ok) '' else law$error)
    if(ok) {parameter$new_density<-law$value[c('shift','scale')];parameters[[length(parameters)+1L]]<-parameter}
    write.csv(do.call(rbind,audit),file.path(work,'calibration_audit.csv'),row.names=FALSE)
  }
  saveRDS(parameters,file.path(root,'parameter_draws.rds'))
  if(!length(parameters)) stop('No calibration fits accepted.')
  test<-nets[membership$test]
  specs<-data.frame(network_id=membership$test,n_nodes=vapply(test,network::network.size,numeric(1)))
  prediction<-stage('prediction_graphs',list(specs=specs,parameters=parameters,
    regime='new_market_uncertain',cfg=cfg,seed=cfg$prediction_seed+fold*10000L+4000L),
    file.path(root,'new_market_uncertain'),'prediction')
  if(!prediction$ok) next
  truth<-as.data.frame(do.call(rbind,lapply(test,pooled_statistics)));truth$network_id<-membership$test
  scores<-score_predictions(prediction$value,truth,cfg$bootstrap_replicates*cfg$effect_draws*cfg$graphs_per_effect)
  scores$fold<-fold;all_scores[[length(all_scores)+1L]]<-scores
  write.csv(do.call(rbind,all_scores),file.path(work,'scores.csv'),row.names=FALSE)
}
cat('Calibration-only validation saved to',work,'; original fit objects were not modified.\n')
