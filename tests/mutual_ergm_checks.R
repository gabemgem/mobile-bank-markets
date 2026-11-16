# Small, handcrafted inputs exercise the entire pipeline without survey data.
root <- normalizePath(".")
source("scripts/mutual_ergm_functions.R")
tmp <- tempfile("mutual-ergm-checks-")
dir.create(tmp)
dir.create(file.path(tmp, "scripts"))
file.copy(file.path(root, "scripts", c("mutual_ergm.R", "mutual_ergm_functions.R")),
          file.path(tmp, "scripts"))
dir.create(file.path(tmp, "data"))
dir.create(file.path(tmp, "experiments/configs"), recursive = TRUE)
cfg <- dget("experiments/configs/mutual_ergm.R")
cfg$models <- cfg$models["density"]
cfg$diagnostic_draws <- 4L
cfg$burnin <- 256L
cfg$interval <- 128L
cfg$replicates <- 2L
dput(cfg, file.path(tmp, "experiments/configs/mutual_ergm.R"))
net <- network::network.initialize(10, directed = FALSE)
network::add.edges(net, c(1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4),
                        c(2, 3, 4, 5, 6, 7, 8, 9, 5, 6, 7, 8))
# Node 10 is an isolate, and the second graph is empty: retain both in input.
records <- data.frame(fit_id = c("fixture-a", "fixture-b"))
empty <- network::network.initialize(6, directed = FALSE)
catalog <- export_mutual_draws(list(net, empty), records, file.path(tmp, "data"))
catalog$network_type <- "observed-undirected-mutual-stated-willingness"
write.csv(catalog, file.path(tmp, "data/networks.csv"), row.names = FALSE)
loaded <- read_mutual_library(file.path(tmp, "data"))
stopifnot(length(loaded) == 2, graph_statistics(loaded[[1]])[["n_isolates"]] == 1,
          network::network.size(loaded[[2]]) == 6)
setwd(tmp)
run <- function(...) {
  status <- system2(file.path(R.home("bin"), "Rscript"),
    c("scripts/mutual_ergm.R", ...), stdout = "check.log", stderr = "check-errors.log")
  if (status != 0) {
    cat(readLines("check.log"), readLines("check-errors.log"), sep = "\n")
    stop("Pipeline subprocess failed")
  }
}
run("fit")
summary <- read.csv("local-ergm/fit_summary.csv")
stopifnot(identical(sort(summary$status), sort(c("ready_for_review", "skipped"))))
checkpoint <- tools::md5sum("local-ergm/case-00001/result.rds")
run("fit")
stopifnot(identical(checkpoint, tools::md5sum("local-ergm/case-00001/result.rds")))
run("generate", "--model", "density")
run("generate", "--model", "density", "--out", "second-library")
files <- c("nodes.csv", "edges.csv", "networks.csv")
stopifnot(identical(unname(tools::md5sum(file.path("synthetic-networks", files))),
                    unname(tools::md5sum(file.path("second-library", files)))))
generated <- read.csv("synthetic-networks/networks.csv")
stopifnot(nrow(generated) == cfg$replicates,
          all(generated$n_nodes == 10), !"source_market" %in% names(generated))
study <- jsonlite::read_json("local-ergm/synthetic_study.json")
stopifnot(length(study$parameters$`selected-market`) == cfg$replicates,
          study$base$`network-source` == "Imported synthetic")
set.seed(724)
a <- matrix(runif(24 * 24) < 0.25, 24)
a[lower.tri(a, diag = TRUE)] <- FALSE
structural <- network::network(a | t(a), directed = FALSE)
dir.create("structural-check")
result <- callr::r(function(helper, net, cfg, folder) {
  source(helper)
  fit_mutual_case(net, "edges + gwdegree(0.5, fixed = TRUE) + gwesp(0.5, fixed = TRUE)",
                  cfg, 724L, 725L, folder)
}, args = list(helper = file.path(root, "scripts/mutual_ergm_functions.R"),
               net = structural, cfg = cfg, folder = normalizePath("structural-check")),
   timeout = 120, stdout = "structural.log", stderr = "structural-errors.log")
if (result$status != "ready_for_review") stop(paste(result$status, result$reason))
stopifnot(file.exists("structural-check/mcmc.pdf"), file.exists("structural-check/gof.pdf"))
bad <- read.csv("data/edges.csv")
write.csv(rbind(bad, bad[1, ]), "data/edges.csv", row.names = FALSE)
stopifnot(inherits(try(read_mutual_library("data"), silent = TRUE), "try-error"))
setwd(root)
cat("PASS: isolates, empty-graph exclusion, structural fitting, MCMC/GOF diagnostics, resume, reproducible exports, study config, duplicate-edge rejection.\n")
cat("Check artifacts:", tmp, "\n")
