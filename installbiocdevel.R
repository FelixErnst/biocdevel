source("https://bioconductor.org/biocLite.R")
biocLite(ask=FALSE)
biocLite("BiocCheck")
biocLite(c("devtools","testthat","roxygen2","assertive",
           "covr",
           "dplyr","RDAVIDWebService","limma","LSD","kSamples",
           "gplots","kohonen"))