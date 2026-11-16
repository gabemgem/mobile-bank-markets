# Run from ABM. Fits and diagnostics stay under an ignored local working directory.
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  options <- list(input = 'data', config = 'experiments/configs/pooled_mutual_ergm.R',
                  work = 'local-pooled-ergm', model = NULL, phase = 'all')
  if (length(args) && args[1] == '--help') {
    cat('Rscript scripts/pooled_mutual_ergm.R [--input data] [--config path] [--work local-pooled-ergm]\n',
        '  [--model density|degree|degree_closure] [--phase all|fit|diagnose]\n')
    return(invisible(NULL))
  }
  if (length(args) %% 2) stop('Options require values.')
  if (length(args)) for (i in seq(1, length(args), 2)) {
    key <- sub('^--', '', args[i])
    if (!startsWith(args[i], '--') || !key %in% names(options)) stop('Unknown option: ', args[i])
    options[[key]] <- args[i + 1]
  }
  stopifnot(options$phase %in% c('all','fit','diagnose'))
  for (package in c('ergm','ergm.multi','network','igraph','callr','coda'))
    if (!requireNamespace(package, quietly = TRUE)) stop('Install R package: ', package)
  helpers <- normalizePath(c('scripts/mutual_ergm_functions.R','scripts/pooled_mutual_ergm_functions.R'))
  for (helper in helpers) source(helper)
  cfg <- dget(options$config)
  stopifnot(identical(cfg$models, dget('experiments/configs/mutual_ergm.R')$models))
  for (key in setdiff(names(cfg), 'models')) {
    stopifnot(length(cfg[[key]]) == 1, is.numeric(cfg[[key]]), is.finite(cfg[[key]]), cfg[[key]] > 0)
  }
  stopifnot(cfg$min_nodes >= 2, cfg$diagnostic_draws >= 2)
  ids <- names(cfg$models)
  if (!is.null(options$model)) {
    stopifnot(options$model %in% ids); ids <- options$model
  }
  files <- file.path(options$input, c('networks.csv','nodes.csv','edges.csv'))
  stopifnot(all(file.exists(files)))
  manifest <- list(config = cfg, input_md5 = unname(tools::md5sum(files)),
    code_md5 = unname(tools::md5sum(c('scripts/pooled_mutual_ergm.R',helpers))),
    packages = vapply(c('ergm','ergm.multi','network','igraph','callr','coda'),
      function(p) as.character(utils::packageVersion(p)), character(1)), R = R.version.string)
  work <- options$work
  path <- file.path(work,'manifest.rds')
  if (file.exists(path)) {
    if (!identical(readRDS(path), manifest)) stop('Inputs/config/code/packages changed; use a new --work directory.')
  } else {
    if (dir.exists(work) && length(list.files(work, all.files = TRUE, no.. = TRUE)))
      stop('Work directory is nonempty without a manifest.')
    dir.create(work, recursive = TRUE, showWarnings = FALSE)
    saveRDS(manifest,path)
    capture.output(sessionInfo(),file = file.path(work,'session.txt'))
  }
  nets <- read_mutual_library(options$input)
  nets <- nets[sort(names(nets))]
  include <- vapply(nets, network::network.size, numeric(1)) >= cfg$min_nodes
  write.csv(data.frame(network_id = names(nets), n_nodes = vapply(nets, network::network.size, numeric(1)),
    n_links = vapply(nets, network::network.edgecount, numeric(1)), included = include),
    file.path(work,'markets.csv'), row.names = FALSE)
  nets <- nets[include]
  if (length(nets) < 2) stop('Pooling requires at least two included markets.')
  cat('Pooled sample:',length(nets),'markets,',sum(vapply(nets,network::network.size,numeric(1))),
      'operators;',sum(!include),'markets excluded. Empty and complete markets are retained.\n')
  call_worker <- function(fun, extra, timeout, folder, stage) {
    started <- proc.time()[['elapsed']]
    result <- tryCatch(callr::r(function(helpers, function_name, extra) {
      for (helper in helpers) source(helper)
      do.call(get(function_name), extra)
    }, args = list(helpers = helpers, function_name = fun, extra = extra), timeout = timeout,
      stdout = file.path(folder,paste0(stage,'.log')), stderr = file.path(folder,paste0(stage,'-errors.log'))),
      error = function(e) list(status = 'error', reason = conditionMessage(e), warnings = character()))
    result$elapsed_seconds <- proc.time()[['elapsed']] - started
    saveRDS(result,file.path(folder,paste0(stage,'_result.rds')))
    cat(' ',stage,':',result$status, result$reason, sprintf('(%.1f s)',result$elapsed_seconds),'\n')
    result
  }
  for (id in ids) {
    folder <- file.path(work,id); dir.create(folder,showWarnings = FALSE)
    folder <- normalizePath(folder)
    index <- match(id,names(cfg$models))
    cat('Candidate:',id,'\n')
    if (options$phase != 'diagnose' && !file.exists(file.path(folder,'fit_result.rds'))) {
      call_worker('pooled_fit', list(nets = nets, terms = cfg$models[[id]], cfg = cfg,
        seed = cfg$fit_seed + index, folder = folder), cfg$fit_timeout, folder, 'fit')
    }
    if (options$phase != 'fit' && file.exists(file.path(folder,'fit.rds')) &&
        !file.exists(file.path(folder,'diagnostic_result.rds'))) {
      call_worker('pooled_diagnostics', list(fit_path = file.path(folder,'fit.rds'), nets = nets,
        cfg = cfg, seed = cfg$diagnostic_seed + index, folder = folder),
        cfg$diagnostic_timeout, folder, 'diagnostic')
    }
  }
  cat('Results:',work,'\nNo production graph library or ABM runs were created.\n')
}
if (sys.nframe() == 0L) main()
