# Two-fold pilot: refit all stages without held-out markets, then predict graphs.
main <- function() {
  args<-commandArgs(trailingOnly=TRUE)
  options<-list(input='data',config='experiments/configs/validate_shrinkage.R',work='local-shrinkage-validation')
  if(length(args) && args[1]=='--help') {
    cat('Rscript scripts/validate_shrinkage.R [--input data] [--config path] [--work local-shrinkage-validation]\n')
    return(invisible(NULL))
  }
  if(length(args) %% 2) stop('Options require values.')
  if(length(args)) for(i in seq(1,length(args),2)) {
    key<-sub('^--','',args[i]);if(!startsWith(args[i],'--') || !key %in% names(options)) stop('Unknown option: ',args[i])
    options[[key]]<-args[i+1]
  }
  packages<-c('ergm','ergm.multi','network','igraph','lme4','callr','coda')
  for(p in packages) if(!requireNamespace(p,quietly=TRUE)) stop('Install R package: ',p)
  cfg<-dget(options$config)
  helper_names<-c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R',
    'shrinkage_mutual_ergm_functions.R','validate_shrinkage_functions.R')
  if(isTRUE(cfg$revised)) helper_names<-c(helper_names,'revised_shrinkage_functions.R')
  helpers<-normalizePath(file.path('scripts',helper_names))
  for(helper in helpers) source(helper)
  regimes<-if(is.null(cfg$regimes)) c('pooled_baseline','calibrated_plugin','calibrated_uncertain','new_market_uncertain') else cfg$regimes
  for(key in c('folds','bootstrap_replicates','effect_draws','graphs_per_effect','posterior_grid',
                'prediction_burnin','prediction_interval'))
    stopifnot(length(cfg[[key]])==1,cfg[[key]]>=1,cfg[[key]]==as.integer(cfg[[key]]))
  stopifnot(cfg$folds>=2,cfg$bootstrap_replicates>=2,cfg$posterior_grid>=257)
  files<-file.path(options$input,c('networks.csv','nodes.csv','edges.csv'));stopifnot(all(file.exists(files)))
  manifest<-list(config=cfg,inputs=unname(tools::md5sum(files)),
    code=unname(tools::md5sum(c('scripts/validate_shrinkage.R',helpers))),
    packages=vapply(packages,function(p) as.character(utils::packageVersion(p)),character(1)),R=R.version.string)
  work<-options$work;path<-file.path(work,'manifest.rds')
  if(file.exists(path)) {
    if(!identical(readRDS(path),manifest)) stop('Inputs/config/code/packages changed; choose a new --work directory.')
  } else {
    if(dir.exists(work) && length(list.files(work,all.files=TRUE,no..=TRUE))) stop('Nonempty work directory without manifest.')
    dir.create(work,recursive=TRUE,showWarnings=FALSE);saveRDS(manifest,path)
    capture.output(sessionInfo(),file=file.path(work,'session.txt'))
  }
  nets<-read_mutual_library(options$input);nets<-nets[sort(names(nets))]
  stopifnot(length(nets)>=cfg$folds,all(vapply(nets,network::network.size,numeric(1))>=2))
  folds<-market_folds(nets,cfg$folds,cfg$split_seed)
  write.csv(folds,file.path(work,'folds.csv'),row.names=FALSE)
  expected<-cfg$bootstrap_replicates*cfg$effect_draws*cfg$graphs_per_effect
  cat(length(nets),'markets;',cfg$folds,'folds;',cfg$bootstrap_replicates,
      'bootstrap refits per fold;',expected,'graphs per held-out market/regime.\n')
  stage<-function(fun,extra,folder,label,timeout=cfg$fit_timeout) {
    dir.create(folder,recursive=TRUE,showWarnings=FALSE);folder<-normalizePath(folder)
    path<-file.path(folder,paste0(label,'_checkpoint.rds'))
    if(file.exists(path)) return(readRDS(path))
    started<-proc.time()[['elapsed']]
    result<-tryCatch({
      value<-callr::r(function(helpers,fun,extra) {
        for(helper in helpers) source(helper)
        do.call(get(fun),extra)
      },args=list(helpers=helpers,fun=fun,extra=extra),timeout=timeout,
      stdout=file.path(folder,paste0(label,'.log')),stderr=file.path(folder,paste0(label,'-errors.log')))
      list(ok=TRUE,value=value,error='')
    },error=function(e) list(ok=FALSE,value=NULL,error=conditionMessage(e)))
    result$elapsed_seconds<-proc.time()[['elapsed']]-started
    saveRDS(result,path)
    status<-if(!result$ok) result$error else if(!is.null(result$value$status)) result$value$status else 'complete'
    cat(' ',basename(folder),label,status,sprintf('(%.1f s)',result$elapsed_seconds),'\n')
    result
  }
  calibration_ok<-function(result) {
    if(!result$ok) return(FALSE)
    messages<-result$value$convergence$lme4$messages
    # A zero-variance bootstrap draw is a legitimate boundary case, not censored.
    messages<-messages[!grepl('boundary.*singular',messages,ignore.case=TRUE)]
    !length(messages) && !any(result$value$convergence$opt!=0) && is.finite(result$value$tau)
  }
  fit_ok<-function(result) result$ok && result$value$status=='ready_for_review'
  audits<-list();all_scores<-list()
  for(fold in seq_len(cfg$folds)) {
    root<-file.path(work,sprintf('fold-%02d',fold));dir.create(root,showWarnings=FALSE)
    test_ids<-folds$network_id[folds$fold==fold];train_ids<-setdiff(names(nets),test_ids)
    stopifnot(!length(intersect(train_ids,test_ids)))
    train<-nets[train_ids];test<-nets[test_ids]
    saveRDS(list(train=train_ids,test=test_ids),file.path(root,'membership.rds'))
    cat('FOLD',fold,':',length(train),'training /',length(test),'held out\n')
    pooled_folder<-file.path(root,'pooled');dir.create(pooled_folder,showWarnings=FALSE)
    baseline<-stage('pooled_fit',list(nets=train,terms=cfg$models[['degree_closure']],cfg=cfg,
      seed=cfg$fit_seed+fold*1000L,folder=normalizePath(pooled_folder)),pooled_folder,'fit')
    if(!fit_ok(baseline)) stop('Training-only pooled initializer failed; inspect ',pooled_folder)
    baseline_beta<-stats::coef(readRDS(file.path(pooled_folder,'fit.rds')))
    point_folder<-file.path(root,'point');dir.create(point_folder,showWarnings=FALSE)
    calibration<-stage('estimate_density_modes',list(nets=train,cfg=cfg),point_folder,'calibration')
    if(!calibration_ok(calibration)) stop('Training density calibration failed; inspect ',point_folder)
    point<-stage('fit_shared_given_modes',list(nets=train,effects=calibration$value$effects,
      beta=baseline_beta,cfg=cfg,seed=cfg$fit_seed+fold*1000L+1L,
      folder=normalizePath(point_folder)),point_folder,'fit')
    if(!fit_ok(point)) stop('Training-only conditional fit failed; inspect ',point_folder)
    point_parameter<-list(id='point',beta=unname(point$value$beta),
      alpha=unname(lme4::fixef(calibration$value$model)),tau=calibration$value$tau)
    if(isTRUE(cfg$revised)) {
      law<-stage('calibrate_new_market',list(nets=train,beta=point_parameter$beta,
        tau=point_parameter$tau,cfg=cfg,seed=cfg$calibration_seed+fold*1000L),
        point_folder,'new_density',cfg$diagnostic_timeout)
      if(!law$ok || law$value$convergence!=0) stop('Training predictive calibration failed; inspect ',point_folder)
      point_parameter$new_density<-law$value[c('shift','scale')]
    }
    parameters<-list()
    for(b in seq_len(cfg$bootstrap_replicates)) {
      folder<-file.path(root,sprintf('bootstrap-%02d',b));dir.create(folder,showWarnings=FALSE)
      set.seed(cfg$bootstrap_seed+fold*1000L+b)
      source_ids<-sample(train_ids,length(train_ids),replace=TRUE)
      stopifnot(all(source_ids %in% train_ids),!any(source_ids %in% test_ids))
      boot<-nets[source_ids];names(boot)<-sprintf('resample-%03d',seq_along(boot))
      write.csv(data.frame(resample_id=names(boot),source_id=source_ids),
        file.path(folder,'resample.csv'),row.names=FALSE)
      mode<-stage('estimate_density_modes',list(nets=boot,cfg=cfg),folder,'calibration')
      result<-NULL
      if(calibration_ok(mode)) result<-stage('fit_shared_given_modes',
        list(nets=boot,effects=mode$value$effects,beta=point_parameter$beta,cfg=cfg,
          seed=cfg$fit_seed+fold*1000L+10L+b,folder=normalizePath(folder)),folder,'fit')
      admitted<-!is.null(result) && fit_ok(result)
      law<-NULL
      if(admitted && isTRUE(cfg$revised)) {
        law<-stage('calibrate_new_market',list(nets=boot,beta=result$value$beta,
          tau=mode$value$tau,cfg=cfg,seed=cfg$calibration_seed+fold*1000L+b),
          folder,'new_density',cfg$diagnostic_timeout)
        admitted<-law$ok && law$value$convergence==0
      }
      audits[[length(audits)+1L]]<-data.frame(fold=fold,bootstrap=b,admitted=admitted,
        calibration_ok=calibration_ok(mode),tau=if(mode$ok) mode$value$tau else NA_real_,
        singular=if(mode$ok) mode$value$singular else NA,
        reason=if(!mode$ok) mode$error else if(!calibration_ok(mode)) 'calibration convergence issue' else
          if(!result$ok) result$error else if(!is.null(law) && !law$ok) law$error else
          if(!is.null(law) && law$value$convergence!=0) 'predictive calibration optimizer issue' else result$value$reason)
      if(admitted) {
        parameter<-list(id=paste0('bootstrap-',b),beta=unname(result$value$beta),
          alpha=unname(lme4::fixef(mode$value$model)),tau=mode$value$tau)
        if(!is.null(law)) parameter$new_density<-law$value[c('shift','scale')]
        parameters[[length(parameters)+1L]]<-parameter
      }
      write.csv(do.call(rbind,audits),file.path(work,'bootstrap_audit.csv'),row.names=FALSE)
    }
    saveRDS(parameters,file.path(root,'parameter_draws.rds'))
    if(!length(parameters)) stop('No admitted bootstrap refits in fold ',fold)
    # Size-only specs are passed to new-market prediction; no held-out edges or counts.
    specs<-data.frame(network_id=test_ids,n_nodes=vapply(test,network::network.size,numeric(1)))
    informed<-specs;informed$n_links<-vapply(test,network::network.edgecount,numeric(1))
    for(regime in regimes) {
      params<-if(regime=='pooled_baseline') list(list(id='point',beta=unname(baseline_beta),alpha=c(0,0),tau=0)) else
        if(regime=='calibrated_plugin') list(point_parameter) else parameters
      input<-if(regime %in% c('calibrated_plugin','calibrated_uncertain')) informed else specs
      folder<-file.path(root,regime)
      predictions<-stage('prediction_graphs',list(specs=input,parameters=params,regime=regime,cfg=cfg,
        seed=cfg$prediction_seed+fold*10000L+match(if(regime=='new_market_raw') 'new_market_uncertain' else regime,
          c('pooled_baseline','calibrated_plugin','calibrated_uncertain','new_market_uncertain'))*1000L),
        folder,'prediction',cfg$diagnostic_timeout)
      if(!predictions$ok) next
      write.csv(predictions$value,file.path(folder,'draws.csv'),row.names=FALSE)
      truth<-as.data.frame(do.call(rbind,lapply(test,pooled_statistics)));truth$network_id<-test_ids
      scores<-score_predictions(predictions$value,truth,expected);scores$fold<-fold
      all_scores[[length(all_scores)+1L]]<-scores
      write.csv(do.call(rbind,all_scores),file.path(work,'scores.csv'),row.names=FALSE)
    }
  }
  cat('Validation complete:',work,'\nAll failures and replicate counts are retained. No production library exported.\n')
}
if(sys.nframe()==0L) main()
