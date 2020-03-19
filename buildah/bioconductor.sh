#!/bin/bash

set -e

##################################################################################
# Variable setup
##################################################################################

IMAGE_NAME="bioconductor"

MAINTAINER="Felix Ernst"
MAINTAINER_MAIL="felix.gm.ernst@outlook.com"

##################################################################################
# Input setup
##################################################################################

##################################################################################
# R build setup
##################################################################################

BUILDPKGS="gdb \
	libxml2-dev \
	python-pip \
	libz-dev \
	liblzma-dev \
	libbz2-dev \
	libpng-dev \
	libmariadb-dev \
	pkg-config \
	fortran77-compiler \
	byacc \
	automake \
	curl \
	libpng-dev \
	libnetcdf-dev \
	libhdf5-serial-dev \
	libfftw3-dev \
	libopenbabel-dev \
	libopenmpi-dev \
	libexempi8 \
	libxt-dev \
	libgdal-dev \
	libjpeg62-turbo-dev \
	libcairo2-dev \
	libtiff5-dev \
	libreadline-dev \
	libgsl0-dev \
	libgslcblas0 \
	libgtk2.0-dev \
	libgl1-mesa-dev \
	libglu1-mesa-dev \
	libgmp3-dev \
	libhdf5-dev \
	libncurses-dev \
	libbz2-dev \
	libxpm-dev \
	liblapack-dev \
	libv8-dev \
	libgtkmm-2.4-dev \
	libmpfr-dev \
	libudunits2-dev \
	libmodule-build-perl \
	libapparmor-dev \
	libgeos-dev \
	libprotoc-dev \
	librdf0-dev \
	libmagick++-dev \
	libsasl2-dev \
	libpoppler-cpp-dev \
	libprotobuf-dev \
	libpq-dev \
	libperl-dev \
	libarchive-extract-perl \
	libfile-copy-recursive-perl \
	libcgi-pm-perl \
	libdbi-perl \
	libdbd-mysql-perl \
	libxml-simple-perl \
	sqlite \
	openmpi-bin \
	mpi-default-bin \
	openmpi-common \
	openmpi-doc \
	tcl8.6-dev \
	tk-dev \
	default-jdk \
	imagemagick \
	tabix \
	ggobi \
	graphviz \
	protobuf-compiler \
	jags \
	xfonts-100dpi \
	xfonts-75dpi \
	biber"

##################################################################################
# Image building
##################################################################################

bioc=$(buildah from --ulimit="nofile=4096" localhost/rstudio:$R_VERSION)

buildah config --created-by "$MAINTAINER" $bioc
buildah config --author "$MAINTAINER <$MAINTAINER_MAIL>" $bioc

R_LIBS=""

# nuke cache dirs before installing pkgs; tip from Dirk E fixes broken img
buildah run $bioc bash -c "rm -f /var/lib/dpkg/available" && 
buildah run $bioc bash -c "rm -rf /var/cache/apt/*" && \
# issues with '/var/lib/dpkg/available' not found
# this will recreate
    buildah run $bioc dpkg --clear-avail && \
# This is to avoid the error
# 'debconf: unable to initialize frontend: Dialog'
    buildah config --env DEBIAN_FRONTEND=noninteractive $bioc

# Update apt-get
buildah run $bioc apt-get update && \
    buildah run $bioc apt-get install -y --no-install-recommends apt-utils && \
    buildah run $bioc apt-get install -y --no-install-recommends $BUILDPKGS && \
    buildah run $bioc apt-get clean && \
    buildah run $bioc bash -c "rm -rf /var/lib/apt/lists/*" && \
## Python installations
    buildah run $bioc apt-get update && \
    buildah run $bioc apt-get -y --no-install-recommends install python-dev && \
    buildah run $bioc pip install wheel && \
	## Install sklearn and pandas on python
    buildah run $bioc pip install setuptools \
sklearn \
pandas \
pyyaml \
cwltool && \
    buildah run $bioc apt-get clean && \
    buildah run $bioc bash -c "rm -rf /var/lib/apt/lists/*" && \

# Install libsbml and xvfb
    buildah config --workingdir /tmp $bioc && \
	## libsbml
    buildah run $bioc curl -O https://s3.amazonaws.com/linux-provisioning/libSBML-5.10.2-core-src.tar.gz && \
    buildah run $bioc tar zxf libSBML-5.10.2-core-src.tar.gz && \
    buildah config --workingdir /tmp/libsbml-5.10.2 $bioc && \
    buildah run $bioc ./configure --enable-layout && \
    buildah run $bioc make && \
    buildah run $bioc make install && \
	## xvfb install
    buildah config --workingdir /tmp $bioc && \
    buildah run $bioc bash -c "curl -SL https://github.com/just-containers/s6-overlay/releases/download/v1.21.8.0/s6-overlay-amd64.tar.gz | tar -xzC /" && \
    buildah run $bioc apt-get update && \
    buildah run $bioc apt-get install -y --no-install-recommends xvfb && \
    buildah run $bioc mkdir -p /etc/services.d/xvfb/ && \
	## Clean libsbml, and tar.gz files
    buildah run $bioc bash -c "rm -rf /tmp/libsbml-5.10.2" && \
    buildah run $bioc bash -c "rm -rf /tmp/libSBML-5.10.2-core-src.tar.gz" && \
	## apt-get clean and remove cache
    buildah run $bioc apt-get clean && \
    buildah run $bioc bash -c "rm -rf /var/lib/apt/lists/*" && \
    buildah run $bioc wget -P /tmp/ https://raw.githubusercontent.com/Bioconductor/bioconductor_docker/master/deps/xvfb_init && \
    buildah run $bioc cp xvfb_init /etc/services.d/xvfb/run && \
    echo "R_LIBS=/usr/local/lib/R/host-site-library:$R_LIBS" | buildah run $bioc bash -c "cat $1 > /usr/local/lib/R/etc/Renviron.site" && \
    echo "options(defaultPackages=c(getOption('defaultPackages'),'BiocManager'))" | buildah run $bioc bash -c "cat $1 >> /usr/local/lib/R/etc/Rprofile.site" && \

    buildah run $bioc wget -P /tmp/ https://raw.githubusercontent.com/Bioconductor/bioconductor_docker/master/install.R && \
    buildah run $bioc R -f install.R && \
## DEVEL: Add sys env variables to DEVEL image
    buildah run $bioc bash -c "curl -O https://raw.githubusercontent.com/Bioconductor/BBS/master/3.11/R_env_vars.sh" && \
    buildah run $bioc bash -c "cat R_env_vars.sh | grep -o '^[^#]*' | sed 's/export //g' >>/etc/environment" && \
    buildah run $bioc bash -c "cat R_env_vars.sh >> /root/.bashrc" && \
    buildah run $bioc bash -c "rm -rf R_env_vars.sh" && \
    buildah run $bioc bash -c "rm -rf /tmp/*" && \
# add command
    buildah config --cmd "/init" $bioc && \
## extract version info from image
    R_VERSION_NO=$(buildah run $bioc Rscript -e "v <- base::R.Version(); cat(if(grepl('unstable',v[['status']])) 'devel' else paste0(v[['major']],'.',v[['status']]))") && \
    R_REV=$(buildah run $bioc Rscript -e "v <- base::R.Version(); cat(v[['svn rev']])") && \
# commit image
    buildah commit $bioc "$IMAGE_NAME:$R_VERSION_NO" && \
    buildah tag "$IMAGE_NAME:$R_VERSION_NO" "$IMAGE_NAME:$R_REV"

echo "Image $IMAGE_NAME:$R_VERSION_NO commited..."
echo $bioc