#!/bin/bash

set -e

##################################################################################
# Variable setup
##################################################################################

IMAGE_NAME="r-ver"

AUTHOR="Felix Ernst"
AUTHOR_MAIL="felix.gm.ernst@outlook.com"

##################################################################################
# Input setup
##################################################################################

while [ $# -gt 0 ]; do
  case "$1" in
    --builddate=*)
      BUILD_DATE="${1#*=}"
      ;;
    --rversion=*)
      R_VERSION="${1#*=}"
      ;;
    *)
      echo "Error: Invalid argument: $1"
      exit 1
  esac
  shift
done

if [ "$R_VERSION" = "" ]
then
    echo "R_VERSION not set. Set it using --rversion"
    exit 1
fi

echo "Starting '$IMAGE_NAME' build for R version '$R_VERSION' / build date '$BUILD_DATE' ... "

if [ $R_VERSION = "devel" ]
then
    R_VERSION_SVN="trunk"
else
    R_VERSION_SVN="tags/"$R_VERSION
fi

##################################################################################
# R build setup
##################################################################################

BUILDPKGS="bash-completion \
        ca-certificates \
        ccache \
        devscripts \
        file \
        fonts-texgyre \
        g++ \
        gfortran \
        gsfonts \
        libblas-dev \
        libbz2-1.0 \
        libcurl4 \
        libicu63 \
        libjpeg62-turbo \
        libopenblas-dev \
        libpangocairo-1.0-0 \
        libpcre3 \
        libpng16-16 \
        libreadline7 \
        libtiff5 \
        liblzma5 \
        locales \
        make \
        unzip \
        zip \
        zlib1g"

BUILDDEPS="curl \
    default-jdk \
    libbz2-dev \
    libcairo2-dev \
    libcurl4-openssl-dev \
    libpango1.0-dev \
    libjpeg-dev \
    libicu-dev \
    libpcre3-dev \
    libpcre2-dev \
    libpng-dev \
    libreadline-dev \
    libtiff5-dev \
    liblzma-dev \
    libx11-dev \
    libxt-dev \
    perl \
    rsync \
    subversion \
    tcl8.6-dev \
    tk8.6-dev \
    texinfo \
    texlive-extra-utils \
    texlive-fonts-recommended \
    texlive-fonts-extra \
    texlive-latex-recommended \
    x11proto-core-dev \
    xauth \
    xfonts-base \
    xvfb \
    zlib1g-dev"

##################################################################################
# Image building
##################################################################################

rver=$(buildah from --ulimit="nofile=4096" debian:buster)
buildah config --label "org.label-schema.license=GPL-2.0" \
    --label "org.label-schema.vcs-url=" \
    --label "org.label-schema.vendor=" \
    --label "maintainer='AUTHOR <$AUTHOR_MAIL>'" $rver
# Author
buildah config --created-by "$AUTHOR" $rver
buildah config --author "$AUTHOR <$AUTHOR_MAIL>" $rver

# Config
buildah config --env LC_ALL=en_US.UTF-8 --env LANG=en_US.UTF-8 --env TERM=xterm $rver

# Packages install
buildah run $rver apt-get update && \
    buildah run $rver apt-get install -y --no-install-recommends $BUILDPKGS && \
    echo "en_US.UTF-8 UTF-8" | buildah run $rver bash -c 'cat $1 >> /etc/locale.gen' && \
    buildah run $rver locale-gen en_US.utf8 && \
    buildah run $rver /usr/sbin/update-locale LANG=en_US.UTF-8 && \
    buildah run $rver apt-get install -y --no-install-recommends $BUILDDEPS && \
    # Download source code
    buildah config --workingdir /tmp $rver && \
    buildah run $rver svn co https://svn.r-project.org/R/$R_VERSION_SVN R-devel && \
    buildah config --workingdir /tmp/R-devel $rver && \
    # Get source code of recommended packages
    buildah run $rver ./tools/rsync-recommended && \
    # Set compiler flags and configure options
    buildah run $rver bash -c 'R_PAPERSIZE=letter \
        R_BATCHSAVE="--no-save --no-restore" \
        R_BROWSER=xdg-open \
        PAGER=/usr/bin/pager \
        PERL=/usr/bin/perl \
        R_UNZIPCMD=/usr/bin/unzip \
        R_ZIPCMD=/usr/bin/zip \
        R_PRINTCMD=/usr/bin/lpr \
        LIBnn=lib \
        AWK=/usr/bin/awk \
        CFLAGS="-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -Wdate-time -D_FORTIFY_SOURCE=2 -g" \
        CXXFLAGS="-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -Wdate-time -D_FORTIFY_SOURCE=2 -g"' && \
    buildah run $rver bash -c './configure --enable-R-shlib \
               --enable-memory-profiling \
               --with-readline \
               --with-blas \
               --with-tcltk \
               --disable-nls \
               --with-recommended-packages' && \
# Build and install
    buildah run $rver make && \
    buildah run $rver make install && \
# Add a default CRAN mirror
    echo 'options(repos = c(CRAN = "https://cran.rstudio.com/"), download.file.method = "libcurl")' | \
        buildah run $rver bash -c 'cat $1 >> /usr/local/lib/R/etc/Rprofile.site' && \
# Add a library directory (for user-installed packages)
    buildah run $rver mkdir -p /usr/local/lib/R/site-library && \
    buildah run $rver chown root:staff /usr/local/lib/R/site-library && \
    buildah run $rver chmod g+ws /usr/local/lib/R/site-library && \
# Fix library path
    echo "R_LIBS_USER='/usr/local/lib/R/site-library'" | \
        buildah run $rver bash -c 'cat $1 >> /usr/local/lib/R/etc/Renviron' && \
    echo "R_LIBS=\${R_LIBS-'/usr/local/lib/R/site-library:/usr/local/lib/R/library:/usr/lib/R/library'}" | \
        buildah run $rver bash -c 'cat $1 >> /usr/local/lib/R/etc/Renviron' && \
# install packages from date-locked MRAN snapshot of CRAN
    [ -z "$BUILD_DATE" ] && BUILD_DATE=$(TZ="America/Los_Angeles" date -I) || true && \
        MRAN=https://mran.microsoft.com/snapshot/${BUILD_DATE} && \
    echo MRAN=$MRAN | buildah run $rver bash -c 'cat $1 >> /etc/environment' && \
    buildah config --env MRAN=$MRAN $rver && \
# MRAN becomes default only in versioned images
# Use littler installation scripts
    buildah run $rver Rscript -e "install.packages(c('littler', 'docopt'), repo = '$MRAN')" && \
    buildah run $rver ln -s /usr/local/lib/R/site-library/littler/examples/install2.r /usr/local/bin/install2.r && \
    buildah run $rver ln -s /usr/local/lib/R/site-library/littler/examples/installGithub.r /usr/local/bin/installGithub.r && \
    buildah run $rver ln -s /usr/local/lib/R/site-library/littler/bin/r /usr/local/bin/r && \
# Clean up from R source install
    buildah config --workingdir / $rver && \
    buildah run $rver bash -c "rm -rf /tmp/*" && \
    buildah run $rver apt-get remove --purge -y $BUILDDEPS && \
    buildah run $rver apt-get autoclean -y && \
    buildah run $rver bash -c "rm -rf /var/lib/apt/lists/*" && \
# extract version info from image
    R_VERSION_NO=$(buildah run $rver Rscript -e "v <- base::R.Version(); cat(if(grepl('unstable',v[['status']])) 'devel' else paste0(v[['major']],'.',v[['status']]))") && \
    R_REV=$(buildah run $rver Rscript -e "v <- base::R.Version(); cat(v[['svn rev']])") && \
    R_VERSION_STRING=$(buildah run $rver Rscript -e "v <- base::R.Version(); cat(v[['version.string']])") && \
# add command
    buildah config --cmd "R" $rver && \
# commit image
    buildah config --label "R_VERSION_STRING=$R_VERSION_STRING" $rver && \
    buildah commit $rver "$IMAGE_NAME:$R_VERSION_NO" && \
    buildah tag "$IMAGE_NAME:$R_VERSION_NO" "$IMAGE_NAME:$R_REV"

echo "Image $IMAGE_NAME:$R_VERSION_NO commited..."
echo $rver