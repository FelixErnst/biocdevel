if (!requireNamespace("BiocManager", quietly = TRUE)){
  install.packages("BiocManager")
}
BiocManager::install("BiocCheck", ask=FALSE)
BiocManager::install(c("devtools","testthat","roxygen2","assertive",
           "covr","ggrepel","ROCR","colorRamps","usethis","sessioninfo",
           "dplyr","RDAVIDWebService","limma","LSD","kSamples",
           "gplots","kohonen"), ask=FALSE)
