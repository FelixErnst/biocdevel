#!/bin/bash

bioc=$(buildah from --ulimit="nofile=4096" localhost/bioconductor:devel)

buildah run $bioc apt-get update && \
    buildah run $bioc apt-get -y install --fix-missing --fix-broken \
        openjdk-11-jdk \
        libpcre++-dev \
        liblzma-dev \
        libbz2-dev \
        imagemagick imagemagick-doc && \
    buildah run $bioc apt-get autoremove -y && \ 
    buildah run $bioc apt-get clean && \
    buildah run $bioc bash -c "rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*"

buildah run $bioc R CMD javareconf
buildah config --workingdir /tmp $bioc
buildah copy $bioc 'installbiocdevel.R' '/tmp/installbiocdevel.R'
buildah run $bioc R -f /tmp/installbiocdevel.R
buildah run $bioc bash -c "rm /tmp/installbiocdevel.R"
buildah commit $bioc "biocdevel:latest"