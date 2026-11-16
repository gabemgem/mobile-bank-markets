# Run from ABM; conditional density-calibrated pilot with explicit checkpoints.
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  options <- list(input = 'data', config = 'experiments/configs/shrinkage_mutual_ergm.R',
    baseline = 'local-pooled-ergm/degree_closure/fit.rds', work = 'local-shrinkage-ergm')
  if(length(args) && args[1] == '--help') {
    cat('Rscript scripts/shrinkage_mutual_ergm.R [--input data] [--config path] [--baseline fit.rds] [--work local-shrinkage-ergm]\n')
    return(invisible(NULL))
  }
  if(length(args) %% 2) stop('Options require values.')
  if(length(args)) for(i in seq(1,length(args),2)) {
    key <- sub('^--','',args[i])
    if(!startsWith(args[i],'--') || !key %in% names(options)) stop('Unknown option: ',args[i])
    options[[key]] <- args[i+1]
  }
  packages <- c('ergm','ergm.multi','network','igraph','callr','coda','lme4')
  for(p in packages) if(!requireNamespace(p,quietly=TRUE)) stop('Install R package: ',p)
  helpers <- normalizePath(c('scripts/mutual_ergm_functions.R',
    'scripts/pooled_mutual_ergm_functions.R','scripts/shrinkage_mutual_ergm_functions.R'))
  for(helper in helpers) source(helper)
  cfg <- dget(options$config)
  stopifnot(cfg$density_quadrature >= 1, cfg$diagnostic_draws >= 2,
            cfg$market_glmm_evaluations > 0, file.exists(options$baseline))
  inputs <- file.path(options$input,c('networks.csv','nodes.csv','edges.csv'))
  stopifnot(all(file.exists(inputs)))
  manifest <- list(method = 'two-stage empirical-Bayes binomial density calibration; conditional ERGM MCMLE',
    config = cfg, inputs = unname(tools::md5sum(inputs)),
    baseline = unname(tools::md5sum(options$baseline)),
    code = unname(tools::md5sum(c('scripts/shrinkage_mutual_ergm.R',helpers))),
    packages = vapply(packages,function(p) as.character(utils::packageVersion(p)),character(1)),
    R = R.version.string)
  work <- options$work; path <- file.path(work,'manifest.rds')
  if(file.exists(path)) {
    if(!identical(manifest,readRDS(path))) stop('Inputs/config/code/packages changed; use a new --work directory.')
  } else {
    if(dir.exists(work) && length(list.files(work,all.files=TRUE,no..=TRUE))) stop('Work directory is nonempty without a manifest.')
    dir.create(work,recursive=TRUE,showWarnings=FALSE);saveRDS(manifest,path)
    capture.output(sessionInfo(),file=file.path(work,'session.txt'))
  }
  nets <- read_mutual_library(options$input);nets <- nets[sort(names(nets))]
  stopifnot(all(vapply(nets,network::network.size,numeric(1)) >= 2))
  mode_path <- file.path(work,'density_modes.rds')
  if(!file.exists(mode_path)) {
    modes <- estimate_density_modes(nets,cfg)
    saveRDS(modes,mode_path)
    write.csv(modes$table,file.path(work,'market_effects.csv'),row.names=FALSE)
  } else modes <- readRDS(mode_path)
  cat('Markets:',length(nets),'; estimated Gaussian density SD:',modes$tau,'\n')
  if(length(modes$convergence$lme4$messages) || any(modes$convergence$opt != 0))
    stop('Density GLMM has convergence messages; inspect density_modes.rds.')
  if(modes$singular) stop('Estimated market variance is on the boundary; no variation supported by this calibration.')
  folder <- normalizePath(work)
  run <- function(fun,extra,stage,timeout) {
    started <- proc.time()[['elapsed']]
    result <- tryCatch(callr::r(function(helpers,fun,extra) {
      for(helper in helpers) source(helper)
      do.call(get(fun),extra)
    },args=list(helpers=helpers,fun=fun,extra=extra),timeout=timeout,
      stdout=file.path(folder,paste0(stage,'.log')),stderr=file.path(folder,paste0(stage,'-errors.log'))),
      error=function(e) list(status='error',reason=conditionMessage(e)))
    result$elapsed_seconds <- proc.time()[['elapsed']]-started
    saveRDS(result,file.path(folder,paste0(stage,'_result.rds')))
    cat(stage,':',result$status,result$reason,sprintf('(%.1f s)',result$elapsed_seconds),'\n')
    result
  }
  if(!file.exists(file.path(folder,'fit_result.rds'))) {
    baseline <- readRDS(options$baseline)
    run('fit_shared_given_modes',list(nets=nets,effects=modes$effects,
      beta=stats::coef(baseline),cfg=cfg,seed=cfg$fit_seed,folder=folder),'fit',cfg$fit_timeout)
  }
  if(file.exists(file.path(folder,'fit.rds')) && !file.exists(file.path(folder,'diagnostic_result.rds')))
    run('pooled_diagnostics',list(fit_path=file.path(folder,'fit.rds'),nets=nets,cfg=cfg,
      seed=cfg$diagnostic_seed,folder=folder),'diagnostic',cfg$diagnostic_timeout)
  cat('Results:',work,'\nConditional diagnostics hold empirical-Bayes market modes fixed. No production library exported.\n')
}
if(sys.nframe()==0L) main()
