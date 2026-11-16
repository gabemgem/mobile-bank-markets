for(h in c('mutual_ergm_functions.R','pooled_mutual_ergm_functions.R',
  'shrinkage_mutual_ergm_functions.R','validate_shrinkage_functions.R','activity_ergm_functions.R',
  'forecast_activity_functions.R','nested_network_functions.R','abm_network_generation_functions.R'))
  source(file.path('scripts',h))
suppressPackageStartupMessages(library(ergm))
cfg<-dget('experiments/configs/generate_abm_networks.R')
cfg$generation_sizes<-2:4;cfg$networks_per_size<-4L;cfg$generation_bootstraps<-2L
cfg$prediction_burnin<-2048L;cfg$prediction_interval<-512L
cfg$activity_burnin<-1024L;cfg$activity_interval<-256L
p<-list(pooled=list(beta=c(-2,-.1,.7,.7)),hub=list(beta=c(-2,-.1,.7,.7),alpha=c(-2,0),tau=.5,
  activity=list(scales=c(0,.75,1.5,2.25),weights=c(.5,.2,.2,.1)),
  count_law=list(shift=0,slope=0,scale=.8,center=2),closure=list(scales=c(0,.5,1,1.5),weights=c(.2,.2,.5,.1))))
draw<-draw_abm_network(4,p,'pooled',cfg,33)$net
stats<-unname(summary(draw~edges+gwdegree(.5,fixed=TRUE)+gwesp(.5,fixed=TRUE)))
energy<-sum(stats*c(p$pooled$beta[1]+p$pooled$beta[2]*log(4),p$pooled$beta[3:4]))
expanded<-c(stats[1],stats[1]*log(4),stats[2:3])
stopifnot(abs(energy-sum(expanded*p$pooled$beta))<1e-10)
# Check the actual pooled extension's model energy, not just its algebraic expansion.
suppressPackageStartupMessages(library(ergm.multi))
other<-network::network.initialize(6,directed=FALSE)
network::add.edges(other,c(1,2,1),c(2,3,3))
basis<-list(a=draw,b=other)
pooled_energy<-sum(unname(summary(pooled_formula(basis,cfg$models[['degree_closure']])))*p$pooled$beta)
direct_energy<-sum(vapply(basis,function(net) {
  values<-unname(summary(net~edges+gwdegree(.5,fixed=TRUE)+gwesp(.5,fixed=TRUE)))
  sum(values*c(p$pooled$beta[1]+p$pooled$beta[2]*log(network::network.size(net)),p$pooled$beta[3:4]))
},numeric(1)))
stopifnot(abs(pooled_energy-direct_energy)<1e-10)
a<-draw_abm_network(4,p,'corrected_hub',cfg,34)
b<-draw_abm_network(4,p,'corrected_hub',cfg,34)
stopifnot(identical(as.matrix(a$net),as.matrix(b$net)),network::network.edgecount(a$net)==a$sampled_count)
out<-tempfile('library-');result<-generate_abm_library(list(p,p),cfg,out)
catalog<-read.csv(file.path(out,'networks.csv'));nodes<-read.csv(file.path(out,'nodes.csv'))
edges<-read.csv(file.path(out,'edges.csv'))
stopifnot(nrow(catalog)==24,all(table(catalog$generator,catalog$n_nodes)==4),
  all(table(catalog$fit_id)==12),!anyDuplicated(catalog$network_id),
  identical(names(catalog)[1:2],c('network_id','network_type')),
  all(table(nodes$network_id)[catalog$network_id]==catalog$n_nodes),
  all(catalog$n_links==as.numeric(table(factor(edges$network_id,levels=catalog$network_id)))))
stopifnot(all(grepl('^node-',nodes$node_id)),all(grepl('^(pooled|corrected-hub)-n',catalog$network_id)))
cat('PASS: pooled size effect, independent reproducible draws, count conservation, balanced anonymous library and isolates.\n')
