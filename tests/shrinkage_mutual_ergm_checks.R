suppressPackageStartupMessages({library(ergm);library(ergm.multi)})
source('scripts/mutual_ergm_functions.R')
source('scripts/pooled_mutual_ergm_functions.R')
source('scripts/shrinkage_mutual_ergm_functions.R')
# A broad handcrafted density range, with empty and complete markets.
sizes <- rep(c(3,6,10),each=5)
probabilities <- rep(c(0,.1,.3,.7,1),3)
set.seed(231)
nets <- lapply(seq_along(sizes),function(i) {
  a<-matrix(FALSE,sizes[i],sizes[i]);a[upper.tri(a)]<-runif(choose(sizes[i],2))<probabilities[i]
  network::network(a|t(a),directed=FALSE)
})
names(nets)<-sprintf('fixture-%02d',seq_along(nets))
cfg<-dget('experiments/configs/shrinkage_mutual_ergm.R')
m<-estimate_density_modes(nets,cfg)
stopifnot(m$tau>0,all(is.finite(m$effects)),identical(names(m$effects),names(nets)))
inside<-is.finite(m$table$raw_shift)
stopifnot(all(abs(m$table$market_effect[inside]) <= abs(m$table$raw_shift[inside])+1e-5),
  all(m$table$market_effect[inside]*m$table$raw_shift[inside]>=-1e-5))
zero<-setNames(rep(0,length(nets)),names(nets));f<-shrinkage_formula(nets,zero)
model<-ergm::ergm_model(f,nw=environment(f)$combined)
eta<-ergm::ergm.eta(c(-2,0,-.5,.5),model$etamap)
stopifnot(identical(unname(eta),c(-2,0,-.5,.5)),
  identical(summary(f),summary(pooled_formula(nets,'edges + gwdegree(0.5, fixed = TRUE) + gwesp(0.5, fixed = TRUE)'))))
index<-which(vapply(nets,network::network.edgecount,numeric(1))>0)[1]
shift<-zero;shift[index]<-.7;f2<-shrinkage_formula(nets,shift)
model2<-ergm::ergm_model(f2,nw=environment(f2)$combined)
stopifnot(ergm::ergm.eta(c(-2,0,-.5,.5),model2$etamap)[3]==1,
  abs(summary(f2)[['offset1']]-.7*network::network.edgecount(nets[[index]]))<1e-8)
# lme4 registers another formula simulation method; explicitly use the ERGM one.
draw<-getFromNamespace('simulate.formula','ergm')(f2,coef=c(-2,0,-.5,.5),nsim=1,seed=232,
  control=ergm::control.simulate.formula(MCMC.burnin=2048,MCMC.interval=1024))
parts<-split_pooled_draw(draw,nets)
stopifnot(length(parts)==length(nets))
cat('PASS: finite empty/complete-market modes, shrinkage toward shared density, fixed ERGM offsets, and block-separated simulation.\n')
