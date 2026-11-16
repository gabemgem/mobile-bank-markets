main<-function() {
  args<-commandArgs(trailingOnly=TRUE)
  opts<-list(input='data',config='experiments/configs/generate_abm_networks.R',
    work='local-abm-network-generation',out='synthetic-networks',phase='all',fit='all')
  if(length(args)%%2) stop('Options require values.')
  if(length(args)) for(i in seq(1,length(args),2)) {
    key<-sub('^--','',args[i]);if(!key %in% names(opts)) stop('Unknown option: ',key)
    opts[[key]]<-args[i+1]
  }
  stopifnot(opts$phase %in% c('all','prepare','fit','generate'))
  helpers<-normalizePath(file.path('scripts',c('mutual_ergm_functions.R',
    'pooled_mutual_ergm_functions.R','shrinkage_mutual_ergm_functions.R',
    'validate_shrinkage_functions.R','activity_ergm_functions.R','forecast_activity_functions.R',
    'nested_network_functions.R','abm_network_generation_functions.R')))
  for(h in helpers) source(h)
  cfg<-dget(opts$config)
  files<-file.path(opts$input,c('networks.csv','nodes.csv','edges.csv'));stopifnot(all(file.exists(files)))
  packages<-c('ergm','ergm.multi','network','igraph','lme4','callr','coda')
  manifest<-list(config=cfg,output=opts$out,inputs=tools::md5sum(files),
    code=tools::md5sum(c('scripts/generate_abm_networks.R',helpers,opts$config)),
    packages=vapply(packages,function(p) as.character(packageVersion(p)),character(1)),R=R.version.string)
  work<-opts$work;path<-file.path(work,'manifest.rds')
  if(file.exists(path)) {
    if(!identical(readRDS(path),manifest)) stop('Inputs/code changed; use a new work directory.')
  } else {
    if(dir.exists(work) && length(list.files(work,all.files=TRUE,no..=TRUE))) stop('Work directory not empty.')
    dir.create(work,recursive=TRUE);saveRDS(manifest,path)
    capture.output(sessionInfo(),file=file.path(work,'session.txt'))
  }
  nets<-read_mutual_library(opts$input);nets<-nets[sort(names(nets))]
  if(opts$phase=='prepare') {
    write.csv(data.frame(network_id=names(nets)),file.path(work,'training_markets.csv'),row.names=FALSE)
    cat('Prepared',length(nets),'markets;',2*length(cfg$generation_sizes)*cfg$networks_per_size,'planned graphs.\n')
    return(invisible(NULL))
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
      cat(basename(folder),label,if(result$ok) 'complete' else result$error,
        sprintf('(%.1f s)\n',result$elapsed_seconds));flush.console()
    }
    if(!result$ok) stop('Stage failed; no fit draws discarded.')
    result$value
  }
  if(opts$phase %in% c('all','fit')) {
    ids<-if(opts$fit=='all') c('point',as.character(seq_len(cfg$generation_bootstraps))) else opts$fit
    stopifnot(all(ids %in% c('point',as.character(seq_len(cfg$generation_bootstraps)))))
    for(id in ids) {
      point<-id=='point';index<-if(point) 0L else as.integer(id)
      folder<-file.path(work,if(point) 'full-data' else sprintf('bootstrap-%02d',index))
      dir.create(folder,showWarnings=FALSE);seed<-cfg$generation_seed+index*10000L
      set.seed(seed);source_ids<-if(point) names(nets) else sample(names(nets),length(nets),replace=TRUE)
      training<-nets[source_ids]
      if(!point) names(training)<-sprintf('resample-%03d',seq_along(training))
      write.csv(data.frame(resample_id=names(training),source_id=source_ids),
        file.path(folder,'resample.csv'),row.names=FALSE)
      stage('nested_fit_pair',list(nets=training,cfg=cfg,seed=seed,folder=normalizePath(folder),
        id=if(point) 'full-data' else paste0('bootstrap-',index)),folder,'pair',cfg$pair_timeout)
    }
  }
  if(opts$phase %in% c('all','generate')) {
    point<-readRDS(file.path(work,'full-data','pair_checkpoint.rds'));stopifnot(point$ok)
    parameters<-lapply(seq_len(cfg$generation_bootstraps),function(i) {
      x<-readRDS(file.path(work,sprintf('bootstrap-%02d',i),'pair_checkpoint.rds'))
      stopifnot(x$ok);x$value
    })
    library_manifest<-file.path(work,'library_manifest.rds')
    if(file.exists(library_manifest)) {
      prior<-readRDS(library_manifest)
      stopifnot(identical(prior$files,tools::md5sum(names(prior$files))))
      cat('Existing generated library verified:',prior$output,'\n');return(invisible(NULL))
    }
    if(dir.exists(opts$out) && length(list.files(opts$out,all.files=TRUE,no..=TRUE)))
      stop('Output directory is not empty; choose a new --out path to preserve existing libraries.')
    dir.create(opts$out,recursive=TRUE,showWarnings=FALSE);output<-normalizePath(opts$out)
    result<-stage('generate_abm_library',list(parameters=parameters,cfg=cfg,out=output),
      file.path(work,'generation'),'library',cfg$prediction_timeout)
    saveRDS(list(output=output,files=tools::md5sum(file.path(output,c('networks.csv','nodes.csv','edges.csv')))),
      file.path(work,'library_manifest.rds'))
    write.csv(aggregate(cbind(n_links,n_isolates,degree_sd,clustering,max_degree)~generator+n_nodes,
      result$catalog,mean),file.path(work,'library_summary.csv'),row.names=FALSE)
    cat('Generated',nrow(result$catalog),'anonymous synthetic graphs in',output,'\n')
  }
}
if(sys.nframe()==0L) main()
