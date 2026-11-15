# Run from the ABM directory, or supply the project root as the first argument.
suppressPackageStartupMessages(library(readxl))
args <- commandArgs(trailingOnly = TRUE)
project <- if (length(args)) normalizePath(args[1]) else normalizePath('..')
source_file <- file.path(project, 'data/Agent Survey Data/02 Datasets/agents_social_network_survey_data.xls')
out <- file.path(project, 'ABM/data')
dir.create(out, recursive = TRUE, showWarnings = FALSE)
raw <- read_excel(source_file, sheet = 1)
normalize_id <- function(x) sub('^([0-9]+_[0-9]+_[0-9]+)-?(AG)', '\\1-\\2', trimws(x))
market_of <- function(x) sub('-.*$', '', x)
raw$agent_id <- normalize_id(raw$agent_id)
raw$ref_agent_id <- normalize_id(raw$ref_agent_id)
stopifnot(!anyNA(raw[c('market','agent_id','ref_agent_id','trade_agent')]))
stopifnot(all(raw$trade_agent %in% c('Yes','No')))
nodes <- unique(data.frame(market=market_of(raw$agent_id), agent_id=raw$agent_id))
nodes <- nodes[order(nodes$market, nodes$agent_id), ]
valid <- raw$agent_id != raw$ref_agent_id & market_of(raw$agent_id) == raw$market &
  market_of(raw$ref_agent_id) == raw$market
e <- raw[valid, ]
directed <- aggregate(e$trade_agent == 'Yes', e[c('market','agent_id','ref_agent_id')], max)
names(directed) <- c('market','source','target','willing')
nonrespondents <- setdiff(unique(raw$ref_agent_id), nodes$agent_id)
directed <- directed[directed$source %in% nodes$agent_id & directed$target %in% nodes$agent_id, ]
yes <- directed[directed$willing == 1, c('market','source','target')]
reverse <- yes[c('market','target','source')]
names(reverse) <- names(yes)
mutual <- merge(yes, reverse, by=c('market','source','target'))
mutual <- mutual[mutual$source < mutual$target, ]
mutual <- mutual[order(mutual$market,mutual$source,mutual$target), ]
stopifnot(!anyDuplicated(mutual), all(mutual$source != mutual$target))
catalog <- data.frame(market=sort(unique(nodes$market)))
catalog$n_nodes <- vapply(catalog$market, function(m) sum(nodes$market == m), integer(1))
catalog$n_mutual_links <- vapply(catalog$market, function(m) sum(mutual$market == m), integer(1))
catalog$n_isolates <- vapply(catalog$market, function(m) {
  edges <- mutual[mutual$market == m, ]
  sum(!nodes$agent_id[nodes$market == m] %in% c(edges$source,edges$target))
}, integer(1))
write.csv(setNames(nodes,c('network_id','node_id')), file.path(out,'nodes.csv'), row.names=FALSE, na='')
write.csv(setNames(mutual,c('network_id','source','target')), file.path(out,'edges.csv'), row.names=FALSE, na='')
catalog <- data.frame(network_id=catalog$market,
                      network_type='observed-undirected-mutual-stated-willingness',
                      n_nodes=catalog$n_nodes,n_links=catalog$n_mutual_links,n_isolates=catalog$n_isolates)
write.csv(catalog, file.path(out,'networks.csv'), row.names=FALSE, na='')
audit <- data.frame(
  item=c('source_file','source_md5','raw_rows','self_or_cross_market_removed',
         'duplicate_directed_reports_collapsed','excluded_nonrespondent_alters',
         'retained_respondents','retained_directed_ties','willing_directed_ties','mutual_undirected_links','markets'),
  value=c('data/Agent Survey Data/02 Datasets/agents_social_network_survey_data.xls',
          unname(tools::md5sum(source_file)),nrow(raw),sum(!valid),
          nrow(e)-nrow(unique(e[c('market','agent_id','ref_agent_id')])),
          length(nonrespondents),nrow(nodes),nrow(directed),nrow(yes),nrow(mutual),nrow(catalog)))
write.csv(audit,file.path(out,'import_audit.csv'),row.names=FALSE)
cat(sprintf('Exported %d markets, %d respondents, %d mutual links; %d isolates retained.\n',
            nrow(catalog), nrow(nodes), nrow(mutual),sum(catalog$n_isolates)))
