main<-function() {
  args<-commandArgs(trailingOnly=TRUE)
  opts<-list(input='data',config='experiments/configs/nested_network_validation.R',
    work='local-nested-validation',benchmark='no',outer='all',prepare='no')
  if(length(args)%%2) stop('Options require values.')
  if(length(args)) for(i in seq(1,length(args),2)) {
    key<-sub('^--','',args[i]);if(!key %in% names(opts)) stop('Unknown option: ',key)
    opts[[key]]<-args[i+1]
  }
  stopifnot(opts$benchmark %in% c('yes','no'),opts$prepare %in% c('yes','no'))
  helpers<-normalizePath(file.path('scripts',c('mutual_ergm_functions.R',
    'pooled_mutual_ergm_functions.R','shrinkage_mutual_ergm_functions.R',
    'validate_shrinkage_functions.R','activity_ergm_functions.R',
    'forecast_activity_functions.R','nested_network_functions.R')))
  for(h in helpers) source(h)
  cfg<-dget(opts$config)
  packages<-c('ergm','ergm.multi','network','igraph','lme4','callr','coda')
  manifest<-list(config=cfg,
    inputs=tools::md5sum(file.path(opts$input,c('networks.csv','nodes.csv','edges.csv'))),
    code=tools::md5sum(c('scripts/validate_nested_networks.R',helpers,opts$config)),
    packages=vapply(packages,function(p) as.character(packageVersion(p)),character(1)),R=R.version.string)
  work<-opts$work;path<-file.path(work,'manifest.rds')
  if(file.exists(path)) {
    if(!identical(readRDS(path),manifest)) stop('Inputs/code/config changed; choose a new work directory.')
  } else {
    if(dir.exists(work) && length(list.files(work,all.files=TRUE,no..=TRUE))) stop('Work directory not empty.')
    dir.create(work,recursive=TRUE);saveRDS(manifest,path)
    capture.output(sessionInfo(),file=file.path(work,'session.txt'))
  }
  stage<-function(fun,extra,folder,label,timeout) {
    dir.create(folder,recursive=TRUE,showWarnings=FALSE);folder<-normalizePath(folder)
    path<-file.path(folder,paste0(label,'_checkpoint.rds'))
    if(file.exists(path)) result<-readRDS(path) else {
      started<-proc.time()[['elapsed']]
      result<-tryCatch(list(ok=TRUE,value=callr::r(function(helpers,fun,extra) {
        for(h in helpers) source(h)
        do.call(get(fun),extra)
      },args=list(helpers=helpers,fun=fun,extra=extra),timeout=timeout,
        stdout=file.path(folder,paste0(label,'.log')),stderr=file.path(folder,paste0(label,'-errors.log')))),
        error=function(e) list(ok=FALSE,error=conditionMessage(e)))
      result$elapsed_seconds<-proc.time()[['elapsed']]-started;saveRDS(result,path)
      cat(basename(dirname(folder)),basename(folder),label,if(result$ok) 'complete' else result$error,
        sprintf('(%.1f s)\n',result$elapsed_seconds));flush.console()
    }
    if(!result$ok) stop('Stage failed. Failures remain recorded; no cases or resamples are dropped.')
    result$value
  }
  nets<-read_mutual_library(opts$input);nets<-nets[sort(names(nets))]
  plan<-nested_splits(nets,cfg)
  plan_path<-file.path(work,'split_plan.rds')
  if(file.exists(plan_path)) stopifnot(identical(readRDS(plan_path),plan)) else {
    saveRDS(plan,plan_path);write.csv(plan$outer,file.path(work,'outer_folds.csv'),row.names=FALSE)
  }
  if(opts$prepare=='yes') {cat('Prepared immutable manifest and split plan.\n');return(invisible(NULL))}
  selected_folds<-if(opts$outer=='all') seq_len(cfg$outer_folds) else as.integer(opts$outer)
  stopifnot(length(selected_folds)>=1,all(selected_folds %in% seq_len(cfg$outer_folds)))
  evaluate<-function(folder,train,validation,parameters,effects,seed) {
    specs<-data.frame(network_id=names(validation),n_nodes=vapply(validation,network::network.size,numeric(1)))
    controls<-cfg;controls$effect_draws<-effects
    scales<-nested_scales(train,cfg);saveRDS(scales,file.path(folder,'scales.rds'))
    draws<-list()
    for(model in c('pooled','hub')) {
      params<-lapply(parameters,`[[`,model)
      fun<-if(model=='pooled') 'nested_pooled_predict' else 'nested_hub_predict'
      draws[[model]]<-stage(fun,list(specs=specs,parameters=params,cfg=controls,seed=seed),
        file.path(folder,model),'prediction',cfg$prediction_timeout)
      write.csv(draws[[model]],file.path(folder,model,'draws.csv'),row.names=FALSE)
    }
    # Only after size-only generation do held-out graph features enter scoring.
    truth<-as.data.frame(do.call(rbind,lapply(validation,activity_statistics)));truth$network_id<-names(validation)
    result<-do.call(rbind,lapply(draws,function(d) nested_score(d,truth,scales,cfg,
      length(parameters)*effects*cfg$graphs_per_effect)))
    write.csv(result,file.path(folder,'scores.csv'),row.names=FALSE);result
  }
  outer_scores<-choices<-list()
  cat(length(nets),'markets;',cfg$outer_folds,'outer folds;',cfg$inner_folds,'inner folds;',
      cfg$outer_bootstraps,'matched outer bootstrap fits per family.\n')
  for(f in selected_folds) {
    split<-plan$splits[[f]];root<-file.path(work,sprintf('outer-%02d',f))
    dir.create(root,showWarnings=FALSE);saveRDS(split,file.path(root,'membership.rds'))
    write.csv(split$inner,file.path(root,'inner_folds.csv'),row.names=FALSE)
    cat('OUTER',f,':',length(split$train),'training /',length(split$test),'test\n');flush.console()
    inner_scores<-list()
    for(i in seq_len(cfg$inner_folds)) {
      validation_ids<-split$inner$network_id[split$inner$fold==i]
      train_ids<-setdiff(split$train,validation_ids)
      stopifnot(!length(intersect(c(train_ids,validation_ids),split$test)),
        !length(intersect(train_ids,validation_ids)))
      train<-nets[train_ids];validation<-nets[validation_ids]
      folder<-file.path(root,sprintf('inner-%02d',i));dir.create(folder,showWarnings=FALSE)
      saveRDS(list(train=train_ids,validation=validation_ids,outer_test=split$test),file.path(folder,'membership.rds'))
      fit_folder<-file.path(folder,'fit');dir.create(fit_folder,showWarnings=FALSE)
      seed<-cfg$nested_seed+f*100000L+i*10000L
      parameter<-stage('nested_fit_pair',list(nets=train,cfg=cfg,seed=seed,
        folder=normalizePath(fit_folder),id='point'),fit_folder,'pair',cfg$pair_timeout)
      d<-evaluate(folder,train,validation,list(parameter),cfg$inner_effects,seed+1000L)
      d$outer_fold<-f;d$inner_fold<-i;inner_scores[[i]]<-d
      if(opts$benchmark=='yes') {
        cat('Benchmark complete. Resume without --benchmark yes to continue from these checkpoints.\n')
        return(invisible(NULL))
      }
    }
    inner<-do.call(rbind,inner_scores);selection<-nested_select(inner,cfg)
    saveRDS(selection,file.path(root,'selection.rds'))
    write.csv(inner,file.path(root,'inner_scores.csv'),row.names=FALSE)
    choices[[f]]<-data.frame(outer_fold=f,selected=selection$selected,
      inner_difference=selection$difference,inner_se=selection$se,n=selection$n)
    write.csv(choices[[f]],file.path(root,'inner_selection.csv'),row.names=FALSE)
    if(opts$outer=='all') write.csv(do.call(rbind,choices),file.path(work,'inner_selections.csv'),row.names=FALSE)
    cat('Selected',selection$selected,'using inner folds only.\n');flush.console()
    train<-nets[split$train];parameters<-list()
    for(b in seq_len(cfg$outer_bootstraps)) {
      seed<-cfg$nested_seed+f*100000L+50000L+b*100L
      set.seed(seed);source_ids<-sample(split$train,length(split$train),replace=TRUE)
      stopifnot(!any(source_ids %in% split$test),all(source_ids %in% split$train))
      boot<-nets[source_ids];names(boot)<-sprintf('resample-%03d',seq_along(boot))
      folder<-file.path(root,sprintf('bootstrap-%02d',b));dir.create(folder,showWarnings=FALSE)
      write.csv(data.frame(resample_id=names(boot),source_id=source_ids),file.path(folder,'resample.csv'),row.names=FALSE)
      parameters[[b]]<-stage('nested_fit_pair',list(nets=boot,cfg=cfg,seed=seed,
        folder=normalizePath(folder),id=paste0('bootstrap-',b)),folder,'pair',cfg$pair_timeout)
    }
    saveRDS(parameters,file.path(root,'parameters.rds'))
    folder<-file.path(root,'test');dir.create(folder,showWarnings=FALSE)
    d<-evaluate(folder,train,nets[split$test],parameters,cfg$outer_effects,
      cfg$nested_seed+f*100000L+90000L)
    d$outer_fold<-f;d$selected<-d$regime==selection$selected;outer_scores[[f]]<-d
    write.csv(d,file.path(folder,'outer_scores.csv'),row.names=FALSE)
    if(opts$outer=='all') write.csv(do.call(rbind,outer_scores),file.path(work,'outer_scores.csv'),row.names=FALSE)
  }
  cat('Nested validation complete. All model fits are partition-specific. No production library generated.\n')
}
if(sys.nframe()==0L) main()
