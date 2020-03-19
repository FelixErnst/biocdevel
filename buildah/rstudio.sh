#!/bin/bash

set -e

##################################################################################
# Variable setup
##################################################################################

IMAGE_NAME="rstudio"

AUTHOR="Felix Ernst"
AUTHOR_MAIL="felix.gm.ernst@outlook.com"

RSTUDIO_VERSION=
S6_VERSION="v1.21.7.0"
PANDOC_TEMPLATES_VERSION="2.9"

##################################################################################
# Input setup
##############################################################################

while [ $# -gt 0 ]; do
  case "$1" in
    --builddate=*)
      BUILD_DATE="${1#*=}"
      ;;
    --rversion=*)
      R_VERSION="${1#*=}"
      ;;
    --rstudioversion=*)
      RSTUDIO_VERSION="${1#*=}"
      ;;
    --s6version=*)
      S6_VERSION="${1#*=}"
      ;;
    --pandoctemplatesversion=*)
      PANDOC_TEMPLATES_VERSION="${1#*=}"
      ;;
    *)
      echo "Error: Invalid argument: $1"
      exit 1
  esac
  shift
done

if [ "$R_VERSION" = "" ]
then
    echo "R_VERSION not set."
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

if [ -z "$RSTUDIO_VERSION" ]; then
    RSTUDIO_URL="https://www.rstudio.org/download/latest/stable/server/bionic/rstudio-server-latest-amd64.deb"
else 
    RSTUDIO_URL="http://download2.rstudio.org/server/bionic/amd64/rstudio-server-${RSTUDIO_VERSION}-amd64.deb"
fi 

BUILDPKGS="file \
        git \
        libapparmor1 \
        libclang-dev \
        libcurl4-openssl-dev \
        libedit2 \
        libssl-dev \
        lsb-release \
        multiarch-support \
        psmisc \
        procps \
        python-setuptools \
        sudo \
        wget \
        gdebi"

##################################################################################
# Image building
##################################################################################

rstudio=$(buildah from --ulimit="nofile=4096" localhost/r-ver:$R_VERSION)

# Author
buildah config --created-by "$AUTHOR" $rstudio
buildah config --author "$AUTHOR <$AUTHOR_MAIL>" $rstudio

# Config
PATH_RSTUDIO=$(buildah run $rstudio printenv PATH)
buildah config --env S6_VERSION=$S6_VERSION --env S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    --env PATH=/usr/lib/rstudio-server/bin:$PATH_RSTUDIO --env PANDOC_TEMPLATES_VERSION=$PANDOC_TEMPLATES_VERSION $rstudio

# expose port
buildah config -p 8787 $rstudio

## Download and install RStudio server & dependencies
## Attempts to get detect latest version, otherwise falls back to version given in $VER
## Symlink pandoc, pandoc-citeproc so they are available system-wide
buildah run $rstudio apt-get update && \
    buildah run $rstudio apt-get install -y --no-install-recommends $BUILDPKGS && \
    buildah config --workingdir /tmp $rstudio && \
    buildah run $rstudio wget -q $RSTUDIO_URL && \    
    buildah run $rstudio bash -c "dpkg -i rstudio-server-*-amd64.deb" && \
    buildah run $rstudio bash -c "rm $(basename $RSTUDIO_URL)" && \
  ## Symlink pandoc & standard pandoc templates for use system-wide
    buildah run $rstudio bash -c "ln -s /usr/lib/rstudio-server/bin/pandoc/pandoc /usr/local/bin" && \
    buildah run $rstudio bash -c "ln -s /usr/lib/rstudio-server/bin/pandoc/pandoc-citeproc /usr/local/bin" && \
    buildah run $rstudio git clone --recursive --branch ${PANDOC_TEMPLATES_VERSION} https://github.com/jgm/pandoc-templates && \
    buildah run $rstudio mkdir -p /opt/pandoc/templates && \
    buildah run $rstudio bash -c "cp -r pandoc-templates*/* /opt/pandoc/templates" && \
    buildah run $rstudio bash -c "rm -rf pandoc-templates*" && \
    buildah run $rstudio mkdir /root/.pandoc && \
    buildah run $rstudio bash -c "ln -s /opt/pandoc/templates /root/.pandoc/templates" && \
    buildah run $rstudio apt-get clean && \
    buildah run $rstudio bash -c "rm -rf /var/lib/apt/lists/" && \
  ## RStudio wants an /etc/R, will populate from $R_HOME/etc
    buildah run $rstudio mkdir -p /etc/R && \
  ## Write config files in $R_HOME/etc
    echo 'options(repos = c(CRAN = "https://cran.rstudio.com/"), download.file.method = "libcurl")
# Configure httr to perform out-of-band authentication if HTTR_LOCALHOST
# is not set since a redirect to localhost may not work depending upon
# where this Docker container is running.
if(is.na(Sys.getenv("HTTR_LOCALHOST", unset=NA))) {
options(httr_oob_default = TRUE)
}' | buildah run $rstudio bash -c "cat $1 >> /usr/local/lib/R/etc/Rprofile.site" && \
    echo "PATH=$PATH_RSTUDIO" | buildah run $rstudio bash -c "cat $1 >> /usr/local/lib/R/etc/Renviron" && \
  ## Need to configure non-root user for RStudio
    buildah run $rstudio useradd rstudio && \
    echo "rstudio:rstudio" | buildah run $rstudio bash -c "chpasswd $1" && \
    buildah run $rstudio mkdir /home/rstudio && \
    buildah run $rstudio chown rstudio:rstudio /home/rstudio && \
    buildah run $rstudio addgroup rstudio staff && \
  ## Prevent rstudio from deciding to use /usr/bin/R if a user apt-get installs a package
    echo 'rsession-which-r=/usr/local/bin/R' | buildah run $rstudio bash -c " cat $1 >> /etc/rstudio/rserver.conf" && \
  ## use more robust file locking to avoid errors when using shared volumes:
    echo 'lock-type=advisory' | buildah run $rstudio bash -c "cat $1 >> /etc/rstudio/file-locks" && \
  ## configure git not to request password each time
    buildah run $rstudio git config --system credential.helper 'cache --timeout=3600' && \
    buildah run $rstudio git config --system push.default simple && \
  ## Set up S6 init system
    buildah run $rstudio wget -P /tmp/ https://github.com/just-containers/s6-overlay/releases/download/${S6_VERSION}/s6-overlay-amd64.tar.gz && \
    buildah run $rstudio tar xzf /tmp/s6-overlay-amd64.tar.gz -C / && \
    buildah run $rstudio mkdir -p /etc/services.d/rstudio && \
    echo '#!/usr/bin/with-contenv bash
## load /etc/environment vars first:
for line in $( cat /etc/environment ) ; do export $line ; done
exec /usr/lib/rstudio-server/bin/rserver --server-daemonize 0' \
| buildah run $rstudio bash -c "cat $1 > /etc/services.d/rstudio/run" && \
    echo '#!/bin/bash
rstudio-server stop' \
| buildah run $rstudio bash -c "cat $1 > /etc/services.d/rstudio/finish" && \
    buildah run $rstudio mkdir -p /home/rstudio/.rstudio/monitored/user-settings && \
    echo 'alwaysSaveHistory="0"
loadRData="0"
saveAction="0"' \
| buildah run $rstudio bash -c "cat $1 > /home/rstudio/.rstudio/monitored/user-settings/user-settings" && \
    buildah run $rstudio chown -R rstudio:rstudio /home/rstudio/.rstudio && \
    buildah run $rstudio wget -P /tmp/ https://raw.githubusercontent.com/rocker-org/rocker-versioned/master/rstudio/userconf.sh && \
    buildah run $rstudio cp userconf.sh /etc/cont-init.d/userconf && \
    buildah run $rstudio wget -P /tmp/ https://raw.githubusercontent.com/rocker-org/rocker-versioned/master/rstudio/add_shiny.sh && \
    buildah run $rstudio cp add_shiny.sh /etc/cont-init.d/add && \
    buildah run $rstudio wget -P /tmp/ https://raw.githubusercontent.com/rocker-org/rocker-versioned/master/rstudio/disable_auth_rserver.conf && \
    buildah run $rstudio cp disable_auth_rserver.conf /etc/rstudio/disable_auth_rserver.conf && \
    buildah run $rstudio wget -P /tmp/ https://raw.githubusercontent.com/rocker-org/rocker-versioned/master/rstudio/pam-helper.sh && \
    buildah run $rstudio cp pam-helper.sh /usr/lib/rstudio-server/bin/pam-helper && \
## automatically link a shared volume for kitematic users
    buildah config --volume "/home/rstudio/kitematic" $rstudio && \
# add command
    buildah config --cmd "/init" $rstudio && \
## extract version info from image
    R_VERSION_NO=$(buildah run $rstudio Rscript -e "v <- base::R.Version(); cat(if(grepl('unstable',v[['status']])) 'devel' else paste0(v[['major']],'.',v[['status']]))") && \
    R_REV=$(buildah run $rstudio Rscript -e "v <- base::R.Version(); cat(v[['svn rev']])") && \
# commit image
    buildah commit $rstudio "$IMAGE_NAME:$R_VERSION_NO" && \
    buildah tag "$IMAGE_NAME:$R_VERSION_NO" "$IMAGE_NAME:$R_REV"

echo "Image $IMAGE_NAME:$R_VERSION_NO commited..."
echo $rstudio