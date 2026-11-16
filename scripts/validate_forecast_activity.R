main<-function() {
  args<-commandArgs(trailingOnly=TRUE)
  opts<-list(input='data',parent='local-activity-validation',
    config='experiments/configs/forecast_activity.R',work='local-forecast-activity')
  if(length(args)%%2) stop('Options require values.')
  if(length(args)) for(i in seq(1,length(args),2)) {
    key<-sub('^--','',args[i]);if(!key %in% names(opts)) stop('Unknown option: ',key)
    opts[[key]]<-args[i+1]
  }
  helpers<-normalizePath(file.path('scripts',c('mutual_ergm_functions.R',
    'pooled_mutual_ergm_functions.R','shrinkage_mutual_ergm_functions.R',
    'validate_shrinkage_functions.R','activity_ergm_functions.R','forecast_activity_functions.R')))
  for(h in helpers) source(h)
  cfg<-dget(opts$config);parent<-readRDS(file.path(opts$parent,'manifest.rds'))
  stopifnot(identical(parent$code,tools::md5sum(names(parent$code))))
  inputs<-unname(tools::md5sum(file.path(opts$input,c('networks.csv','nodes.csv','edges.csv'))))
  stopifnot(identical(inputs,parent$inputs))
  for(key in c('folds','bootstrap_replicates','effect_draws','graphs_per_effect','split_seed'))
    stopifnot(identical(cfg[[key]],parent$config[[key]]))
  parent_files<-unlist(lapply(seq_len(cfg$folds),function(f) {
    root<-file.path(opts$parent,sprintf('fold-%02d',f))
    c(file.path(root,c('parameter_draws.rds','membership.rds')),
      file.path(root,sprintf('bootstrap-%02d',seq_len(cfg$bootstrap_replicates)),'resample.csv'))
  }))
  stopifnot(all(file.exists(parent_files)))
  packages<-c('ergm','ergm.multi','network','igraph','lme4','callr')
  manifest<-list(config=cfg,inputs=inputs,parent=tools::md5sum(parent_files),
    code=tools::md5sum(c('scripts/validate_forecast_activity.R',helpers,opts$config)),
    packages=vapply(packages,function(p) as.character(packageVersion(p)),character(1)),R=R.version.string)
  work<-opts$work;path<-file.path(work,'manifest.rds')
  if(file.exists(path)) {
    if(!identical(readRDS(path),manifest)) stop('Inputs/code changed; use a new work directory.')
  } else {
    if(dir.exists(work) && length(list.files(work,all.files=TRUE,no..=TRUE))) stop('Work directory not empty.')
    dir.create(work,recursive=TRUE);saveRDS(manifest,path)
    capture.output(sessionInfo(),file=file.path(work,'session.txt'))
  }
  stage<-function(fun,extra,folder,label,timeout=600) {
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
      cat(basename(folder),label,if(result$ok) 'complete' else result$error,
        sprintf('(%.1f s)\n',result$elapsed_seconds));flush.console()
    }
    if(!result$ok) stop('Stage failed; no missing draws will be dropped.')
    result
  }
  nets<-read_mutual_library(opts$input);nets<-nets[sort(names(nets))]
  folds<-market_folds(nets,cfg$folds,cfg$split_seed)
  write.csv(folds,file.path(work,'folds.csv'),row.names=FALSE)
  expected<-cfg$bootstrap_replicates*cfg$effect_draws*cfg$graphs_per_effect
  scores<-audit<-count_scores<-list()
  for(f in seq_len(cfg$folds)) {
    root<-file.path(work,sprintf('fold-%02d',f));dir.create(root,showWarnings=FALSE)
    oldroot<-file.path(opts$parent,sprintf('fold-%02d',f))
    member<-readRDS(file.path(oldroot,'membership.rds'))
    stopifnot(setequal(member$test,folds$network_id[folds$fold==f]),
      setequal(member$train,setdiff(names(nets),member$test)),!length(intersect(member$test,member$train)))
    saveRDS(member,file.path(root,'membership.rds'))
    parameters<-readRDS(file.path(oldroot,'parameter_draws.rds'))
    stopifnot(length(parameters)==cfg$bootstrap_replicates)
    cat('FOLD',f,'\n');flush.console()
    for(b in seq_along(parameters)) {
      resample<-read.csv(file.path(oldroot,sprintf('bootstrap-%02d',b),'resample.csv'))
      stopifnot(all(resample$source_id %in% member$train),!any(resample$source_id %in% member$test))
      boot<-nets[resample$source_id];names(boot)<-resample$resample_id
      folder<-file.path(root,sprintf('bootstrap-%02d',b))
      density<-stage('fit_forecast_count',list(nets=boot,parameter=parameters[[b]],cfg=cfg),folder,'count')
      closure<-stage('fit_forecast_closure',list(nets=boot,parameter=parameters[[b]],cfg=cfg,
        seed=cfg$forecast_seed+f*1000L+b),folder,'closure')
      parameters[[b]]$count_law<-density$value;parameters[[b]]$closure<-closure$value
      write.csv(resample,file.path(folder,'resample.csv'),row.names=FALSE)
      audit[[length(audit)+1L]]<-data.frame(fold=f,bootstrap=b,
        shift=density$value$shift,slope=density$value$slope,scale=density$value$scale,
        count_crps=density$value$training_crps,raw_count_crps=density$value$raw_training_crps,
        closure_scale=closure$value$scales,closure_weight=closure$value$weights,
        closure_blend=closure$value$blend,objective=closure$value$objective,
        raw_objective=closure$value$raw_objective,count_seconds=density$elapsed_seconds,
        closure_seconds=closure$elapsed_seconds)
      write.csv(do.call(rbind,audit),file.path(work,'calibration_audit.csv'),row.names=FALSE)
    }
    saveRDS(parameters,file.path(root,'parameter_draws.rds'))
    test<-nets[member$test]
    specs<-data.frame(network_id=member$test,n_nodes=vapply(test,network::network.size,numeric(1)))
    informed<-specs;informed$n_links<-vapply(test,network::network.edgecount,numeric(1))
    truth<-as.data.frame(do.call(rbind,lapply(test,activity_statistics)));truth$network_id<-member$test
    for(regime in c('new_density_activity','new_density_closure','fixed_count_closure')) {
      input<-if(regime=='fixed_count_closure') informed else specs
      seed<-cfg$activity_seed+f*10000L+if(regime=='fixed_count_closure') 1000L else 2000L
      result<-stage('predict_forecast_activity',list(specs=input,parameters=parameters,regime=regime,cfg=cfg,
        seed=seed),file.path(root,regime),'prediction')
      write.csv(result$value,file.path(root,regime,'draws.csv'),row.names=FALSE)
      d<-score_predictions(result$value,truth,expected,
        c('n_links','degree_sd','max_degree','n_isolates','n_components','largest_component','clustering','triangles'))
      stopifnot(all(d$n_draws==expected));d$fold<-f;scores[[length(scores)+1L]]<-d
      write.csv(do.call(rbind,scores),file.path(work,'scores.csv'),row.names=FALSE)
    }
    # Quadrature scores integrate count laws, reducing finite graph-draw noise.
    for(corrected in c(FALSE,TRUE)) for(i in seq_len(nrow(specs))) {
      n<-specs$n_nodes[i];m<-truth$n_links[i];support<-0:choose(n,2)
      cdf<-rowMeans(vapply(parameters,function(p) forecast_count_cdf(n,p,cfg,corrected),numeric(length(support))))
      lower<-support[which(cdf>=.025)[1]];upper<-support[which(cdf>=.975)[1]]
      count_scores[[length(count_scores)+1L]]<-data.frame(network_id=specs$network_id[i],fold=f,
        regime=if(corrected) 'corrected_count' else 'previous_count',observed=m,
        mean=sum(1-cdf),crps=sum((cdf-as.numeric(support>=m))^2),q025=lower,q975=upper,
        covered=m>=lower && m<=upper,width=upper-lower,absolute_error=abs(sum(1-cdf)-m))
    }
    write.csv(do.call(rbind,count_scores),file.path(work,'quadrature_count_scores.csv'),row.names=FALSE)
  }
  cat('Complete. Private development pilot; no production library exported.\n')
}
if(sys.nframe()==0L) main()
