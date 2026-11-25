args <- commandArgs(trailingOnly=TRUE)
if(length(args)!=2) stop('Usage: Rscript experiments/plot_policy_study.R ANALYSIS_DIR FIGURE_DIR')
suppressPackageStartupMessages(library(ggplot2))
analysis <- args[1]; output <- args[2]
dir.create(output,recursive=TRUE,showWarnings=FALSE)
preview <- file.path(analysis,'previews');dir.create(preview,showWarnings=FALSE)
read <- function(name) read.csv(file.path(analysis,name),check.names=FALSE)
sizes <- read('size-outcomes.csv'); outcomes <- read('outcomes.csv')
networks <- read('network-structure.csv'); contrasts <- read('size-contrasts.csv')
family_names <- c(pooled='Pooled primary',corrected_hub='Corrected hub sensitivity')
policy_names <- c(isolated='Isolated',external='External only',`network-s0`='Network sharing',
                  `fallback-s0`='Sharing + external',`fallback-s100`='Sharing + external, full subsidy')
colors <- c(isolated='#78828A',external='#4269AA',`network-s0`='#087C79',`fallback-s0`='#BF651E',`fallback-s100`='#75449B')
core <- c('isolated','external','network-s0','fallback-s0')
theme_set(theme_minimal(base_size=12,base_family='sans') + theme(
  plot.title=element_text(face='bold',size=18,color='#172D38',margin=margin(b=8)),
  plot.subtitle=element_text(size=11,color='#52666C',margin=margin(b=15)),
  plot.caption=element_text(size=10,color='#52666C',hjust=0,margin=margin(t=15)),
  panel.grid.minor=element_blank(),panel.grid.major.x=element_blank(),
  strip.text=element_text(face='bold',size=12,color='#172D38'),
  legend.position='bottom',legend.title=element_blank(),
  plot.background=element_rect(fill='#FFFDF8',color=NA),
  panel.background=element_rect(fill='#FFFDF8',color=NA),
  plot.margin=margin(20,22,18,18)))
family <- function(data) {data$family<-factor(data$generator,levels=names(family_names),labels=family_names);data}
lines <- function() list(scale_color_manual(values=colors,breaks=names(policy_names),labels=policy_names),
                        scale_linetype_manual(values=c(isolated='dotted',external='longdash',`network-s0`='solid',`fallback-s0`='solid',`fallback-s100`='dotdash'),
                                              breaks=names(policy_names),labels=policy_names),
                        guides(color=guide_legend(nrow=2,byrow=TRUE)))
plots <- list()
save <- function(name,p,width=11,height=5.7) {
  plots[[name]] <<- p
  ggsave(file.path(output,paste0(name,'.svg')),p,width=width,height=height,device=grDevices::svg,bg='#FFFDF8')
  ggsave(file.path(preview,paste0(name,'.png')),p,width=width,height=height,dpi=150,bg='#FFFDF8')
}
for(metric in c('service_pct','deposit_service_pct','withdrawal_service_pct')) {
  label <- c(service_pct='Customer value',deposit_service_pct='Deposit value',withdrawal_service_pct='Withdrawal value')[[metric]]
  d <- family(subset(sizes,policy %in% core));d$policy<-factor(d$policy,levels=core)
  p <- ggplot(d,aes(n,.data[[metric]],color=policy,linetype=policy))+geom_line(linewidth=.9)+
    geom_point(size=1.5)+facet_wrap(~family,nrow=1)+lines()+
    scale_x_continuous(breaks=c(2,6,12,18,24))+scale_y_continuous(limits=c(0,65),breaks=seq(0,60,15))+
    labs(title=paste(label,'served by market size'),subtitle='Unsubsidized policies; the same graphs and demand seeds are paired across policies.',
         x='Kiosks in the market',y='Requested value served (%)',
         caption='Each point averages 20 graph draws x 20 seeds at that size. Lines connect tested sizes; no empirical forecasts.')
  save(paste0('size-',metric),p)
}
d <- family(subset(sizes,policy %in% c('external','network-s0','fallback-s0')))
d$policy<-factor(d$policy,levels=c('external','network-s0','fallback-s0'))
save('paired-effects',ggplot(d,aes(n,gain_pp,color=policy,fill=policy,linetype=policy))+
  geom_hline(yintercept=0,color='#8B9398',linetype='dashed')+
  geom_ribbon(aes(ymin=gain_pp_q10,ymax=gain_pp_q90),alpha=.09,color=NA)+geom_line(linewidth=.95)+
  facet_wrap(~family,nrow=1)+lines()+scale_fill_manual(values=colors,guide='none')+
  scale_x_continuous(breaks=c(2,6,12,18,24))+labs(title='Policy gains vary across synthetic networks',
    subtitle='Mean paired gain over isolation, with the middle 80% of seed-averaged graph effects.',
    x='Kiosks in the market',y='Change in value served (percentage points)',
    caption='Ribbons show 10th-90th graph percentiles, not confidence intervals. Twenty graph draws per size.'))
for(mode in c('cumulative','interval')) {
  d <- family(outcomes[outcomes$mode==mode & outcomes$policy %in% c(core,'fallback-s100'),])
  d$policy<-factor(d$policy,levels=c(core,'fallback-s100'))
  d$time <- if(mode=='cumulative') d$tick else c(`100`=50,`250`=175,`500`=375,`1000`=750)[as.character(d$tick)]
  save(paste0('time-',mode),ggplot(d,aes(time,service_pct,color=policy,linetype=policy))+
    geom_line(linewidth=.9)+geom_point(size=2)+facet_wrap(~family,nrow=1)+lines()+
    scale_x_continuous(breaks=if(mode=='cumulative') c(100,250,500,1000) else c(50,175,375,750),
                       labels=if(mode=='cumulative') c('100','250','500','1,000') else c('1-100','101-250','251-500','501-1,000'))+
    scale_y_continuous(limits=c(20,55),breaks=seq(20,50,10))+
    labs(title=if(mode=='cumulative') 'Cumulative service through time' else 'Service within successive time windows',
         subtitle=if(mode=='cumulative') 'Startup dynamics are included; no economic burn-in is discarded.' else 'Interval percentages are recalculated from changes in served and requested values.',
         x=if(mode=='cumulative') 'Completed ticks' else 'Time window (points placed at window midpoints)',
         y='Requested value served (%)',caption='Equal graph and size weights within each family. Full subsidy injects additional cash throughout the run.'))
}
d <- subset(outcomes,mode=='cumulative' & tick==1000 & grepl('^(network|fallback)-',policy))
d$subsidy <- as.integer(sub('.*-s','',d$policy));d$mechanism<-ifelse(grepl('^network',d$policy),'Network sharing','Sharing + external')
d <- family(d)
base <- d[d$subsidy==0,c('generator','mechanism','service_pct')];names(base)[3]<-'baseline'
d <- merge(d,base,by=c('generator','mechanism'));d$increment<-d$service_pct-d$baseline
save('subsidies',ggplot(d,aes(subsidy,increment,color=mechanism,group=mechanism))+
  geom_hline(yintercept=0,color='#8B9398',linetype='dashed')+geom_line(linewidth=1)+geom_point(size=2.8)+
  facet_wrap(~family,nrow=1)+scale_x_continuous(breaks=c(0,50,100),limits=c(0,100))+
  scale_color_manual(values=c('Network sharing'='#087C79','Sharing + external'='#BF651E'))+
  labs(title='Subsidies add modest average service gains',subtitle='Each curve compares subsidy levels within the same rebalancing policy.',
       x='Share of the 1% commission paid by the sponsor (%)',y='Gain over zero subsidy (percentage points)',
       caption='Only three subsidy levels were tested. Lines do not predict intermediate levels; negative network-specific effects remain possible.'))
save('subsidy-cost',ggplot(d,aes(subsidy,subsidy_per_kiosk,color=mechanism,group=mechanism))+
  geom_line(linewidth=1)+geom_point(size=2.8)+facet_wrap(~family,nrow=1)+
  scale_x_continuous(breaks=c(0,50,100),limits=c(0,100))+
  scale_color_manual(values=c('Network sharing'='#087C79','Sharing + external'='#BF651E'))+
  labs(title='Full subsidy costs much more than half subsidy',subtitle='Mean settled sponsor spending per kiosk over 1,000 ticks.',
       x='Share of commission covered (%)',y='Sponsor cash per kiosk (model units)',
       caption='Initial cash is 500 per kiosk. Sponsor payments add cash; external-provider and staffing operating costs are not modeled.'))
d <- family(subset(contrasts,contrast %in% c('network_vs_isolated','add_network','add_external','network_full','fallback_full')))
contrast_names <- c(network_vs_isolated='Sharing vs isolation',add_network='Add sharing to external',add_external='Add external to sharing',network_full='Full subsidy, sharing',fallback_full='Full subsidy, hybrid')
d$comparison<-factor(d$contrast,levels=rev(names(contrast_names)),labels=rev(contrast_names))
save('harm',ggplot(d,aes(n,comparison,fill=harm_pct))+geom_tile(color='#FFFDF8',linewidth=.7)+
  facet_wrap(~family,ncol=1)+scale_x_continuous(breaks=seq(2,24,2),expand=c(0,0))+
  scale_fill_gradient(low='#E5F0EB',high='#A14A1C',limits=c(0,max(d$harm_pct)),name='Graphs harmed (%)')+
  theme(legend.title=element_text(size=10))+labs(title='A positive mean does not mean every network benefits',
    subtitle='A graph is harmed if its mean paired service change is below -0.1 percentage points after averaging 20 seeds.',
    x='Kiosks in the market',y=NULL,caption='Each cell summarizes 20 graph draws; percentages change in 5-point steps. These are model scenarios, not surveyed markets.'),height=7)
d <- family(networks)
save('structure',ggplot(d,aes(isolate_pct,network_gain,color=n))+geom_hline(yintercept=0,linetype='dashed',color='#8B9398')+
  geom_point(alpha=.55,size=1.9)+facet_wrap(~family,nrow=1)+scale_color_gradient(low='#326AA8',high='#BF651E',name='Kiosks')+
  labs(title='Sharing gains depend on the generated network',subtitle='Each dot is one synthetic graph, averaged over its 20 simulation seeds.',
       x='Kiosks with no sharing partners (%)',y='Sharing gain over isolation (percentage points)',
       caption='Association only: size, connectivity, hub structure and synthetic spring geography change together. No causal isolation effect is estimated.'))
pdf(file.path(output,'policy-study-figures.pdf'),width=11,height=6.5,onefile=TRUE)
for(p in plots) print(p)
dev.off()
cat('Rendered',length(plots),'figures, PNG previews and a multipage PDF.\n')
