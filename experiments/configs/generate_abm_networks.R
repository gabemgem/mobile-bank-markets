local({
  cfg<-dget('experiments/configs/nested_network_validation.R')
  cfg$generation_sizes<-2:24
  cfg$networks_per_size<-20L
  cfg$generation_bootstraps<-4L
  cfg$generation_seed<-1701001L
  cfg
})
