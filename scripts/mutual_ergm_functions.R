# Helpers shared by the command-line pipeline, isolated R workers, and checks.
read_mutual_library <- function(folder) {
  read <- function(name) read.csv(file.path(folder, name), colClasses = "character",
                                  check.names = FALSE)
  catalog <- read("networks.csv")
  nodes <- read("nodes.csv")
  edges <- read("edges.csv")
  stopifnot(all(c("network_id", "network_type") %in% names(catalog)),
            all(c("network_id", "node_id") %in% names(nodes)),
            all(c("network_id", "source", "target") %in% names(edges)),
            nrow(catalog) > 0, !anyDuplicated(catalog$network_id),
            all(catalog$network_type == "observed-undirected-mutual-stated-willingness"),
            all(nodes$network_id %in% catalog$network_id),
            all(edges$network_id %in% catalog$network_id))
  out <- lapply(catalog$network_id, function(id) {
    ids <- sort(nodes$node_id[nodes$network_id == id])
    e <- edges[edges$network_id == id, ]
    stopifnot(length(ids) > 0, !anyNA(ids), all(nzchar(ids)), !anyDuplicated(ids),
              all(e$source %in% ids), all(e$target %in% ids),
              all(e$source != e$target))
    pairs <- data.frame(a = pmin(e$source, e$target), b = pmax(e$source, e$target))
    stopifnot(!anyDuplicated(pairs))
    net <- network::network.initialize(length(ids), directed = FALSE)
    # Vertex order preserves isolates; source identifiers stay outside fit objects.
    if (nrow(e)) network::add.edges(net, match(e$source, ids), match(e$target, ids))
    net
  })
  names(out) <- catalog$network_id
  out
}

graph_statistics <- function(net) {
  a <- as.matrix(net, matrix.type = "adjacency")
  g <- igraph::graph_from_adjacency_matrix(a, mode = "undirected", diag = FALSE)
  d <- igraph::degree(g)
  components <- igraph::components(g)
  clustering <- igraph::transitivity(g, type = "global")
  c(n_nodes = length(d), n_links = igraph::ecount(g),
    density = igraph::edge_density(g), mean_degree = mean(d),
    degree_sd = if (length(d) > 1) sd(d) else 0,
    n_isolates = sum(d == 0), n_components = components$no,
    largest_component = max(components$csize),
    clustering = if (is.finite(clustering)) clustering else 0)
}

with_pdf <- function(path, draw) {
  grDevices::pdf(path, width = 9, height = 7)
  on.exit(grDevices::dev.off())
  draw()
}

fit_mutual_case <- function(net, terms, cfg, seed, diagnostic_seed, folder) {
  suppressPackageStartupMessages(library(ergm))
  warnings <- character()
  capture <- function(expr) withCallingHandlers(expr, warning = function(w) {
    warnings <<- unique(c(warnings, conditionMessage(w)))
    invokeRestart("muffleWarning")
  })
  formula <- stats::as.formula(paste("net ~", terms), env = environment())
  fit <- capture(ergm::ergm(formula, eval.loglik = FALSE,
    control = ergm::control.ergm(seed = seed, parallel = 1, MPLE.check = FALSE,
                               MCMLE.maxit = cfg$max_iterations)))
  estimate <- stats::coef(fit)
  se <- sqrt(diag(stats::vcov(fit)))
  problems <- c(
    if (isTRUE(fit$failure)) "estimation failure",
    if (any(!is.finite(estimate)) || any(abs(estimate) > cfg$max_abs_coefficient))
      "nonfinite or extreme coefficient",
    if (any(!is.finite(se)) || any(se > cfg$max_standard_error))
      "nonfinite or extreme standard error",
    if (any(grepl("did not converge|not converged|did not mix|degenera", warnings,
                  ignore.case = TRUE))) "convergence or mixing warning"
  )
  coefficients <- data.frame(term = names(estimate), estimate = unname(estimate),
                             standard_error = unname(se))
  write.csv(coefficients, file.path(folder, "coefficients.csv"), row.names = FALSE)
  saveRDS(fit, file.path(folder, "fit.rds"))
  diagnostic_error <- NULL
  if (!length(problems)) {
    diagnostic_error <- tryCatch({
      if (!ergm::is.dyad.independent(fit)) {
        with_pdf(file.path(folder, "mcmc.pdf"), function()
          capture(ergm::mcmc.diagnostics(fit, which = "plots")))
      }
      set.seed(diagnostic_seed)
      gof <- capture(ergm::gof(fit, GOF = ~ degree + esp + distance + model,
        control = ergm::control.gof.ergm(nsim = cfg$diagnostic_draws,
          MCMC.burnin = cfg$burnin, MCMC.interval = cfg$interval)))
      saveRDS(gof, file.path(folder, "gof.rds"))
      with_pdf(file.path(folder, "gof.pdf"), function() plot(gof))
      capture.output(print(gof), file = file.path(folder, "gof.txt"))
      draws <- capture(stats::simulate(fit, nsim = cfg$diagnostic_draws,
        seed = diagnostic_seed + 1L,
        control = ergm::control.simulate.ergm(MCMC.burnin = cfg$burnin,
                                            MCMC.interval = cfg$interval)))
      simulated <- as.data.frame(do.call(rbind, lapply(draws, graph_statistics)))
      observed <- graph_statistics(net)
      envelope <- data.frame(metric = names(observed), observed = unname(observed),
        mean = vapply(simulated, mean, numeric(1)),
        q025 = vapply(simulated, quantile, numeric(1), probs = 0.025),
        q975 = vapply(simulated, quantile, numeric(1), probs = 0.975))
      write.csv(simulated, file.path(folder, "diagnostic_draws.csv"), row.names = FALSE)
      write.csv(envelope, file.path(folder, "envelope.csv"), row.names = FALSE)
      NULL
    }, error = function(e) conditionMessage(e))
  }
  if (any(grepl("did not converge|not converged|did not mix|degenera", warnings,
                ignore.case = TRUE))) problems <- unique(c(problems, "convergence or mixing warning"))
  list(status = if (length(problems)) "problem_fit" else if (!is.null(diagnostic_error))
         "diagnostic_error" else "ready_for_review",
       reason = paste(c(problems, diagnostic_error), collapse = "; "), warnings = warnings)
}

generate_mutual_draws <- function(fit_path, seeds, cfg) {
  suppressPackageStartupMessages(library(ergm))
  fit <- readRDS(fit_path)
  # Separate chains and explicit seeds make each graph individually reproducible.
  lapply(seeds, function(seed) stats::simulate(fit, nsim = 1, seed = seed,
    control = ergm::control.simulate.ergm(MCMC.burnin = cfg$burnin,
                                        MCMC.interval = cfg$interval)))
}

export_mutual_draws <- function(draws, records, out) {
  nodes <- edges <- catalogs <- vector("list", length(draws))
  for (i in seq_along(draws)) {
    id <- sprintf("synthetic-%05d", i)
    a <- as.matrix(draws[[i]], matrix.type = "adjacency")
    vertex_ids <- sprintf("node-%04d", seq_len(nrow(a)))
    endpoints <- which(a != 0 & upper.tri(a), arr.ind = TRUE)
    nodes[[i]] <- data.frame(network_id = id, node_id = vertex_ids)
    edges[[i]] <- data.frame(network_id = rep(id, nrow(endpoints)),
      source = vertex_ids[endpoints[, 1]], target = vertex_ids[endpoints[, 2]])
    catalogs[[i]] <- cbind(data.frame(network_id = id,
      network_type = "synthetic-ergm-undirected-mutual-stated-willingness"),
      records[i, , drop = FALSE], as.data.frame(as.list(graph_statistics(draws[[i]]))))
  }
  write.csv(do.call(rbind, nodes), file.path(out, "nodes.csv"), row.names = FALSE)
  write.csv(do.call(rbind, edges), file.path(out, "edges.csv"), row.names = FALSE)
  catalog <- do.call(rbind, catalogs)
  write.csv(catalog, file.path(out, "networks.csv"), row.names = FALSE)
  catalog
}
