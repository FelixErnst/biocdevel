FROM bioconductor/devel_core2:latest


RUN apt-get update && \
    apt-get -y install --fix-missing --fix-broken \
    openjdk-11-jdk \
    libpcre++-dev \
    liblzma-dev \
    libbz2-dev \
    imagemagick imagemagick-doc && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN R RMD javareconf

ADD installbiocdevel.R /tmp/
RUN R -f /tmp/installbiocdevel.R
