# Independent graph draws; estimation artifacts never enter the import library.
draw_abm_network<-function(n,pair,generator,cfg,seed) {
  suppressPackageStartupMessages(library(ergm))
  set.seed(seed)
  if(generator=='pooled') {
    beta<-pair$pooled$beta;net<-network::network.initialize(n,directed=FALSE)
    f<-net~edges+gwdegree(.5,fixed=TRUE)+gwesp(.5,fixed=TRUE)
    draw<-getFromNamespace('simulate.formula','ergm')(f,
      coef=c(beta[1]+beta[2]*log(n),beta[3:4]),nsim=1,seed=seed,
      control=ergm::control.simulate.formula(MCMC.burnin=cfg$prediction_burnin,
        MCMC.interval=cfg$prediction_interval))
    return(list(net=draw,activity_sd=0,closure_multiplier=1,sampled_count=NA_integer_))
  }
  stopifnot(generator=='corrected_hub')
  p<-pair$hub
  sigma<-sample(p$activity$scales,1,prob=p$activity$weights)
  activity<-rnorm(n,0,sigma);law<-p$count_law
  probability<-plogis(p$alpha[1]+p$alpha[2]*log(n)+law$shift+
    law$slope*(log(n)-law$center)+rnorm(1,0,p$tau)*law$scale)
  m<-rbinom(1,choose(n,2),probability)
  q<-sample(p$closure$scales,1,prob=p$closure$weights)
  beta<-p$beta;beta[4]<-beta[4]*q
  list(net=activity_graphs(n,m,activity,beta,1,cfg,seed+1L)[[1]],
    activity_sd=sigma,closure_multiplier=q,sampled_count=m)
}

generate_abm_library<-function(parameters,cfg,out) {
  stopifnot(length(parameters)==cfg$generation_bootstraps,
    cfg$networks_per_size%%length(parameters)==0)
  registry<-expand.grid(replicate=seq_len(cfg$networks_per_size),
    n_nodes=cfg$generation_sizes,generator=c('pooled','corrected_hub'),stringsAsFactors=FALSE)
  nodes<-edges<-catalog<-vector('list',nrow(registry));warnings<-character()
  for(i in seq_len(nrow(registry))) {
    row<-registry[i,];index<-1L+(row$replicate-1L)%%length(parameters)
    seed<-cfg$generation_seed+1000000L+i*100L
    generated<-withCallingHandlers(draw_abm_network(row$n_nodes,parameters[[index]],
      row$generator,cfg,seed),warning=function(w) {
        warnings<<-unique(c(warnings,conditionMessage(w)));invokeRestart('muffleWarning')
      })
    net<-generated$net;a<-as.matrix(net,matrix.type='adjacency')
    stopifnot(nrow(a)==row$n_nodes,all(diag(a)==0),all(a==t(a)),all(a %in% c(0,1)))
    id<-sprintf('%s-n%02d-r%02d',gsub('_','-',row$generator),row$n_nodes,row$replicate)
    vertex_ids<-sprintf('node-%04d',seq_len(nrow(a)))
    ends<-which(a!=0 & upper.tri(a),arr.ind=TRUE)
    nodes[[i]]<-data.frame(network_id=id,node_id=vertex_ids)
    edges[[i]]<-data.frame(network_id=rep(id,nrow(ends)),
      source=vertex_ids[ends[,1]],target=vertex_ids[ends[,2]])
    catalog[[i]]<-cbind(data.frame(network_id=id,
      network_type=paste0('synthetic-',gsub('_','-',row$generator),'-mutual-stated-willingness'),
      generator=row$generator,role=if(row$generator=='pooled') 'primary' else 'sensitivity',
      replicate=row$replicate,graph_seed=seed,fit_id=paste0('bootstrap-',index),
      activity_sd=generated$activity_sd,closure_multiplier=generated$closure_multiplier),
      as.data.frame(t(activity_statistics(net))))
    if(row$generator=='corrected_hub') stopifnot(network::network.edgecount(net)==generated$sampled_count)
  }
  catalog<-do.call(rbind,catalog)
  dir.create(out,recursive=TRUE,showWarnings=FALSE)
  write.csv(catalog,file.path(out,'networks.csv'),row.names=FALSE)
  write.csv(do.call(rbind,nodes),file.path(out,'nodes.csv'),row.names=FALSE)
  write.csv(do.call(rbind,edges),file.path(out,'edges.csv'),row.names=FALSE)
  list(catalog=catalog,warnings=warnings)
}
