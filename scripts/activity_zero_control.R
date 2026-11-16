# Exact-count ablation: retain all controls but remove extra latent activity.
args<-commandArgs(trailingOnly=TRUE)
work<-if(length(args)) args[1] else 'local-activity-validation'
helpers<-normalizePath(file.path('scripts',c('mutual_ergm_functions.R',
  'pooled_mutual_ergm_functions.R','shrinkage_mutual_ergm_functions.R',
  'validate_shrinkage_functions.R','activity_ergm_functions.R')))
for(h in helpers) source(h)
manifest<-readRDS(file.path(work,'manifest.rds'));cfg<-manifest$config
stopifnot(identical(unname(tools::md5sum(file.path('data',c('networks.csv','nodes.csv','edges.csv')))),manifest$inputs))
nets<-read_mutual_library('data');scores<-list()
control_manifest<-list(code=tools::md5sum(c('scripts/activity_zero_control.R',helpers)),
  parent=tools::md5sum(file.path(work,'manifest.rds')),
  parameters=tools::md5sum(file.path(work,sprintf('fold-%02d',seq_len(cfg$folds)),'parameter_draws.rds')))
path<-file.path(work,'control_manifest.rds')
if(file.exists(path)) stopifnot(identical(readRDS(path),control_manifest)) else saveRDS(control_manifest,path)
for(f in seq_len(cfg$folds)) {
  root<-file.path(work,sprintf('fold-%02d',f))
  params<-readRDS(file.path(root,'parameter_draws.rds'))
  params<-lapply(params,function(p) {p$activity$weights<-c(1,0,0,0);p})
  member<-readRDS(file.path(root,'membership.rds'));test<-nets[member$test]
  specs<-data.frame(network_id=member$test,n_nodes=vapply(test,network::network.size,numeric(1)),
    n_links=vapply(test,network::network.edgecount,numeric(1)))
  folder<-file.path(root,'fixed_count_zero');dir.create(folder,showWarnings=FALSE)
  path<-file.path(folder,'prediction.rds')
  if(file.exists(path)) d<-readRDS(path) else {
    started<-proc.time()[['elapsed']]
    d<-callr::r(function(helpers,specs,params,cfg,seed) {
      for(h in helpers) source(h)
      predict_activity(specs,params,'fixed_count_activity',cfg,seed)
    },args=list(helpers=helpers,specs=specs,params=params,cfg=cfg,seed=cfg$activity_seed+f*10000L+1000L),
      timeout=600,stdout=file.path(folder,'prediction.log'),stderr=file.path(folder,'prediction-errors.log'))
    saveRDS(d,path)
    cat('Zero control fold',f,proc.time()[['elapsed']]-started,'seconds\n')
  }
  d$regime<-'fixed_count_zero';write.csv(d,file.path(folder,'draws.csv'),row.names=FALSE)
  truth<-as.data.frame(do.call(rbind,lapply(test,activity_statistics)));truth$network_id<-member$test
  s<-score_predictions(d,truth,cfg$bootstrap_replicates*cfg$effect_draws*cfg$graphs_per_effect,
    c('n_links','degree_sd','max_degree','n_isolates','n_components','largest_component','clustering','triangles'))
  stopifnot(all(s$n_draws==s$expected_draws));s$fold<-f;scores[[f]]<-s
}
write.csv(do.call(rbind,scores),file.path(work,'zero_scores.csv'),row.names=FALSE)
