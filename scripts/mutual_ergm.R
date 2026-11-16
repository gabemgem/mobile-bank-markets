# Run from ABM: Rscript scripts/mutual_ergm.R fit|generate [--option value]
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  usage <- paste(
    "From ABM: Rscript scripts/mutual_ergm.R fit|generate [--option value]",
    "Options: --config experiments/configs/mutual_ergm.R --input data",
    "         --work local-ergm --model density|degree|degree_closure",
    "         --limit 2 --retry true --out synthetic-networks",
    "Fit defaults to all models/markets. Generate requires --model.", sep = "\n")
  if (!length(args) || args[1] %in% c("--help", "help")) {
    cat(usage, "\n"); return(invisible(NULL))
  }
  command <- args[1]
  if (!command %in% c("fit", "generate")) stop(usage)
  options <- list(config = "experiments/configs/mutual_ergm.R", input = "data",
                  work = "local-ergm", model = NULL, limit = Inf, retry = "false",
                  out = "synthetic-networks")
  rest <- args[-1]
  if (length(rest) %% 2) stop("Options require values.\n", usage)
  if (length(rest)) for (i in seq(1, length(rest), by = 2)) {
    key <- sub("^--", "", rest[i])
    if (!startsWith(rest[i], "--") || !key %in% names(options)) stop("Unknown option: ", rest[i])
    options[[key]] <- rest[i + 1]
  }
  for (package in c("network", "ergm", "igraph", "callr", "jsonlite")) {
    if (!requireNamespace(package, quietly = TRUE)) stop("Install required R package: ", package)
  }
  helper <- normalizePath("scripts/mutual_ergm_functions.R", mustWork = TRUE)
  source(helper)
  cfg <- dget(options$config)
  allowed <- c("edges", "edges + gwdegree(0.5, fixed = TRUE)",
               "edges + gwdegree(0.5, fixed = TRUE) + gwesp(0.5, fixed = TRUE)")
  stopifnot(length(cfg$models) > 0, !is.null(names(cfg$models)),
            !anyDuplicated(names(cfg$models)), all(grepl("^[a-z][a-z0-9_]*$", names(cfg$models))),
            all(cfg$models %in% allowed))
  positive <- c("min_nodes", "fit_seed", "diagnostic_seed", "generation_seed",
                "timeout_seconds", "max_iterations", "diagnostic_draws", "burnin",
                "interval", "replicates", "max_abs_coefficient", "max_standard_error")
  for (key in positive) stopifnot(length(cfg[[key]]) == 1, is.finite(cfg[[key]]), cfg[[key]] > 0)
  integers <- setdiff(positive, c("timeout_seconds", "max_abs_coefficient", "max_standard_error"))
  for (key in integers) stopifnot(cfg[[key]] == as.integer(cfg[[key]]))
  stopifnot(cfg$diagnostic_draws >= 2, cfg$min_nodes >= 2)
  limit <- as.numeric(options$limit)
  stopifnot(length(limit) == 1, !is.na(limit), limit > 0,
            is.infinite(limit) || limit == as.integer(limit), options$retry %in% c("true", "false"))
  if (!is.null(options$model) && !options$model %in% names(cfg$models)) stop("Unknown model")
  inputs <- file.path(options$input, c("networks.csv", "nodes.csv", "edges.csv"))
  if (!all(file.exists(inputs))) stop("Missing input CSVs. Run scripts/export_market_networks.R first.")
  fingerprint <- list(config = cfg, inputs = unname(tools::md5sum(inputs)),
    code = unname(tools::md5sum(c("scripts/mutual_ergm.R", helper))),
    packages = vapply(c("network", "ergm", "igraph", "callr", "jsonlite"),
                      function(p) as.character(utils::packageVersion(p)), character(1)),
    r_version = R.version.string)
  work <- options$work
  manifest <- file.path(work, "manifest.rds")
  if (file.exists(manifest)) {
    if (!identical(readRDS(manifest), fingerprint))
      stop("Inputs, configuration, packages, or code changed. Use a new --work directory.")
  } else {
    if (command == "generate") stop("Run fit first with this configuration and work directory.")
    if (dir.exists(work) && length(list.files(work, all.files = TRUE, no.. = TRUE)))
      stop("Work directory is nonempty without a manifest; choose a new --work directory.")
    dir.create(work, recursive = TRUE, showWarnings = FALSE)
    saveRDS(fingerprint, manifest)
    capture.output(sessionInfo(), file = file.path(work, "session.txt"))
  }
  nets <- read_mutual_library(options$input)
  ids <- sort(names(nets))
  cases <- expand.grid(network_id = ids, model_id = names(cfg$models), stringsAsFactors = FALSE)
  cases$case_id <- sprintf("case-%05d", seq_len(nrow(cases)))
  cases$fit_seed <- cfg$fit_seed + seq_len(nrow(cases))
  cases$diagnostic_seed <- cfg$diagnostic_seed + seq_len(nrow(cases))
  stopifnot(max(c(cases$fit_seed, cases$diagnostic_seed,
                 cfg$generation_seed + nrow(cases) * cfg$replicates)) < .Machine$integer.max - 1)
  cases$folder <- file.path(work, cases$case_id)
  write.csv(cases, file.path(work, "case_index.csv"), row.names = FALSE)
  selected <- cases$network_id %in% head(ids, limit)
  if (!is.null(options$model)) selected <- selected & cases$model_id == options$model
  case_results <- function() lapply(cases$folder, function(folder) {
    path <- file.path(folder, "result.rds")
    if (file.exists(path)) readRDS(path) else list(status = "not_run", reason = "", warnings = character())
  })
  write_summary <- function() {
    rows <- case_results()
    summary <- cbind(cases[c("case_id", "network_id", "model_id", "fit_seed", "diagnostic_seed")],
      status = vapply(rows, `[[`, character(1), "status"),
      reason = vapply(rows, `[[`, character(1), "reason"),
      elapsed_seconds = vapply(rows, function(x) if (is.null(x$elapsed_seconds))
        NA_real_ else x$elapsed_seconds, numeric(1)),
      warnings = vapply(rows, function(x) paste(x$warnings, collapse = " | "), character(1)))
    write.csv(summary, file.path(work, "fit_summary.csv"), row.names = FALSE)
    summary
  }
  if (command == "fit") {
    for (i in which(selected)) {
      folder <- cases$folder[i]
      previous <- file.path(folder, "result.rds")
      if (file.exists(previous)) {
        status <- readRDS(previous)$status
        if (options$retry == "false" || status == "ready_for_review") next
      }
      dir.create(folder, recursive = TRUE, showWarnings = FALSE)
      net <- nets[[cases$network_id[i]]]
      n <- network::network.size(net)
      m <- network::network.edgecount(net)
      cat(sprintf("[%s] %s / %s: %d nodes, %d edges\n", cases$case_id[i],
                  cases$network_id[i], cases$model_id[i], n, m))
      started <- proc.time()[["elapsed"]]
      result <- if (n < cfg$min_nodes || m == 0 || m == choose(n, 2)) {
        list(status = "skipped", reason = "below minimum size, empty, or complete network",
             warnings = character())
      } else tryCatch(callr::r(function(helper, net, terms, cfg, seed, diagnostic_seed, folder) {
        source(helper)
        fit_mutual_case(net, terms, cfg, seed, diagnostic_seed, folder)
      }, args = list(helper = helper, net = net, terms = cfg$models[[cases$model_id[i]]],
        cfg = cfg, seed = cases$fit_seed[i], diagnostic_seed = cases$diagnostic_seed[i],
        folder = normalizePath(folder)), timeout = cfg$timeout_seconds,
        stdout = file.path(folder, "worker.log"), stderr = file.path(folder, "worker-errors.log")),
        error = function(e) list(status = "error", reason = conditionMessage(e), warnings = character()))
      result$elapsed_seconds <- proc.time()[["elapsed"]] - started
      saveRDS(result, previous)
      cat("  ", result$status, result$reason, sprintf("(%.1f s)", result$elapsed_seconds), "\n")
      write_summary()
    }
    summary <- write_summary()
    print(table(summary$status))
    cat("Review fit_summary.csv and each case's diagnostics in", work, "\n")
    return(invisible(summary))
  }
  if (is.null(options$model)) stop("Generation requires an explicit --model after reviewing diagnostics.")
  summary <- write_summary()
  eligible <- selected & summary$status == "ready_for_review"
  if (!any(eligible)) stop("No reviewed-model candidates have usable fits and complete diagnostics.")
  if (dir.exists(options$out) && length(list.files(options$out, all.files = TRUE, no.. = TRUE)))
    stop("Output directory is nonempty; choose a new --out directory. No library was overwritten.")
  parent <- dirname(options$out)
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  parent <- normalizePath(parent, winslash = "/", mustWork = TRUE)
  staging <- tempfile(".ergm-library-", tmpdir = parent)
  dir.create(staging)
  staging <- normalizePath(staging, winslash = "/", mustWork = TRUE)
  stopifnot(dirname(staging) == parent, startsWith(basename(staging), ".ergm-library-"))
  on.exit({
    if (dir.exists(staging)) {
      stopifnot(dirname(normalizePath(staging, winslash = "/", mustWork = TRUE)) == parent)
      unlink(staging, recursive = TRUE)
    }
  }, add = TRUE)
  draws <- records <- list()
  for (i in which(eligible)) {
    seeds <- cfg$generation_seed + (i - 1L) * cfg$replicates + seq_len(cfg$replicates)
    cat("Generating", cfg$replicates, "graphs from", cases$case_id[i], "\n")
    generated <- callr::r(function(helper, fit_path, seeds, cfg) {
      source(helper); generate_mutual_draws(fit_path, seeds, cfg)
    }, args = list(helper = helper, fit_path = normalizePath(file.path(cases$folder[i], "fit.rds")),
                   seeds = seeds, cfg = cfg), timeout = cfg$timeout_seconds)
    draws <- c(draws, generated)
    records[[length(records) + 1L]] <- data.frame(fit_id = cases$case_id[i],
      model_id = cases$model_id[i], terms = cfg$models[[cases$model_id[i]]],
      graph_seed = seeds, fit_seed = cases$fit_seed[i],
      burnin = cfg$burnin, interval = cfg$interval, ergm_version = fingerprint$packages[["ergm"]])
  }
  catalog <- export_mutual_draws(draws, do.call(rbind, records), staging)
  # Public provenance contains anonymous case IDs; the market crosswalk stays in work.
  dput(fingerprint, file.path(staging, "provenance.R"))
  if (dir.exists(options$out)) unlink(options$out, recursive = FALSE)
  if (!file.rename(staging, options$out)) stop("Could not install generated library.")
  selection <- cbind(summary, selected = selected, used = eligible,
                     graph_replicates = ifelse(eligible, cfg$replicates, 0L))
  write.csv(selection, file.path(work, "generation_selection.csv"), row.names = FALSE)
  study <- list(mode = "grid", ticks = 500L, seeds = c(11L, 22L, 33L, 44L, 55L),
    warmup_runs = 2L, base = list(`network-source` = "Imported synthetic"),
    parameters = list(`selected-market` = as.list(catalog$network_id),
      `sharing-mode` = c("No sharing", "Network sharing", "All-to-all sharing"),
      `settlement-delay` = 0:2))
  jsonlite::write_json(study, file.path(work, "synthetic_study.json"), auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("Exported %d graphs to %s; %d selected cases excluded or not run.\n",
              nrow(catalog), options$out, sum(selected & !eligible)))
  cat("ABM study:", file.path(work, "synthetic_study.json"), "with",
      nrow(catalog) * 3 * 3 * length(study$seeds), "runs. Preview/benchmark before running.\n")
  cat("NetLogo's Imported synthetic mode reads synthetic-networks/. Alternate --out paths are staging libraries.\n")
}

if (sys.nframe() == 0L) main()
