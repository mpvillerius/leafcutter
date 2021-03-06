nb_anova=function(x,counts) {
  
}

#' Perform pairwise differential splicing analysis.
#'
#' Parallelization across tested clusters is achieved using foreach/doMC, so the number of threads that will be used is determined by the cores argument passed to registerDoMC.
#'
#' @param counts An [introns] x [samples] matrix of counts. The rownames must be of the form chr:start:end:cluid. If the counts file comes from the leafcutter clustering code this should be the case already.
#' @param x A [samples] numeric vector, should typically be 0s and 1s, although in principle scaling shouldn't matter.
#' @param max_cluster_size Don't test clusters with more introns than this
#' @param min_samples_per_intron Ignore introns used (i.e. at least one supporting read) in fewer than n samples
#' @param min_samples_per_group Require this many samples in each group to have at least min_coverage reads
#' @param min_coverage Require min_samples_per_group samples in each group to have at least this many reads
#' @param timeout Maximum time (in seconds) allowed for a single optimization run
#'
#' @return A per cluster list of results. Clusters that were not tested will be represented by a string saying why.
#' @import foreach
#' @importFrom R.utils evalWithTimeout
#' @export
differential_splicing=function(counts, x, max_cluster_size=10, min_samples_per_intron=5, min_samples_per_group=4, min_coverage=20, timeout=10) {
  
  intron_names=rownames(counts)
  introns=as.data.frame(do.call(rbind,strsplit(intron_names,":")))
  colnames(introns)=c("chr","start","end","clu")
  cluster_ids=paste(introns$chr,introns$clu,sep = ":")
  
  cluster_sizes=as.data.frame(table(cluster_ids))
  clu_names=as.character(cluster_sizes$cluster_ids)
  cluster_sizes=cluster_sizes$Freq
  names(cluster_sizes)=clu_names
  
  zz <- file( "/dev/null", open = "wt")
  sink(zz)
  sink(zz, type = "message")
  
  results=foreach (cluster_name=clu_names, .errorhandling = "pass") %dopar% {
    if (cluster_sizes[cluster_name] > max_cluster_size)
      return("Too many introns in cluster")
    cluster_counts=t(counts[ cluster_ids==cluster_name, ])
    sample_totals=rowSums(cluster_counts)
    samples_to_use=sample_totals>0 
    if (sum(samples_to_use)<=1 ) 
      return("<=1 sample with coverage>0")
    sample_totals=sample_totals[samples_to_use]
    if (sum(sample_totals>=min_coverage)<=1) 
      return("<=1 sample with coverage>min_coverage")
    x_subset=x[samples_to_use]
    cluster_counts=cluster_counts[samples_to_use,]
    introns_to_use=colSums(cluster_counts>0)>=min_samples_per_intron # only look at introns used by at least 5 samples
    if ( sum(introns_to_use)<2 ) 
      return("<2 introns used in >=min_samples_per_intron samples")
    cluster_counts=cluster_counts[,introns_to_use]
    ta=table(x_subset[sample_totals>=min_coverage])
    if (sum(ta >= min_samples_per_group)<2) # at least two groups have this (TODO: continuous x)
      return("Not enough valid samples") 
    tryCatch({
      res <- R.utils::evalWithTimeout( { 
        nb_anova(x_subset,cluster_counts)
      }, timeout=timeout, onTimeout="silent" ) 
      if (is.null(res)) "timeout" else res
    }, error=function(g) as.character(g))
  }
  
  sink(type="message")
  sink()
  
  statuses=leafcutter_status(results)
  
  cat("Differential splicing summary:\n")
  print(as.data.frame(table(statuses)))
  
  names(results)=clu_names
  results
}

