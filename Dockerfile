FROM bioconductor/devel_core2


RUN apt-get update && \
    apt-get -y install --fix-missing --fix-broken \
    openjdk-8-jdk \
    libpcre++-dev \
    liblzma-dev \
    libbz2-dev
RUN R RMD javareconf

ADD installbiocdevel.R /tmp/
RUN R -f /tmp/installbiocdevel.R
