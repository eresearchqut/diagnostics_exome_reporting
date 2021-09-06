# Stage 1 Build VEP
FROM rocker/shiny:4.1.1 as builder
# Update aptitude and install some required packages
# a lot of them are required for Bio::DB::BigFile
RUN apt-get update && apt-get -y install \
    build-essential \
    git \
    libpng-dev \
    zlib1g-dev \
    libbz2-dev \
    liblzma-dev \
    perl \
    perl-base \
    unzip \
    wget && \
    rm -rf /var/lib/apt/lists/*

# Setup VEP environment
ENV OPT /opt/vep
ENV OPT_SRC $OPT/src
ENV HTSLIB_DIR $OPT_SRC/htslib
ENV BRANCH release/104

# Working directory
WORKDIR $OPT_SRC
# Clone/download repositories/libraries
RUN if [ "$BRANCH" = "master" ]; \
    then export BRANCH_OPT=""; \
    else export BRANCH_OPT="-b $BRANCH"; \
    fi && \
    # Get ensembl cpanfile in order to get the list of the required Perl libraries
    wget -q "https://raw.githubusercontent.com/Ensembl/ensembl/$BRANCH/cpanfile" -O "ensembl_cpanfile" && \
    # Clone ensembl-vep git repository
    git clone $BRANCH_OPT --depth 1 https://github.com/Ensembl/ensembl-vep.git && chmod u+x ensembl-vep/*.pl && \
    # Clone ensembl-variation git repository and compile C code
    git clone $BRANCH_OPT --depth 1 https://github.com/Ensembl/ensembl-variation.git && \
    mkdir var_c_code && \
    cp ensembl-variation/C_code/*.c ensembl-variation/C_code/Makefile var_c_code/ && \
    rm -rf ensembl-variation && \
    chmod u+x var_c_code/* && \
    # Clone bioperl-ext git repository - used by Haplosaurus
    git clone --depth 1 https://github.com/bioperl/bioperl-ext.git && \
    # Download ensembl-xs - it contains compiled versions of certain key subroutines used in VEP
    wget https://github.com/Ensembl/ensembl-xs/archive/2.3.2.zip -O ensembl-xs.zip && \
    unzip -q ensembl-xs.zip && mv ensembl-xs-2.3.2 ensembl-xs && rm -rf ensembl-xs.zip && \
    # Clone/Download other repositories: bioperl-live is needed so the cpanm dependencies installation from the ensembl-vep/cpanfile file takes less disk space
    ensembl-vep/travisci/get_dependencies.sh && \
    # Only keep the bioperl-live "Bio" library
    mv bioperl-live bioperl-live_bak && mkdir bioperl-live && mv bioperl-live_bak/Bio bioperl-live/ && rm -rf bioperl-live_bak && \
    ## A lot of cleanup on the imported libraries, in order to reduce the docker image ##
    rm -rf Bio-HTS/.??* Bio-HTS/Changes Bio-HTS/DISCLAIMER Bio-HTS/MANIFEST* Bio-HTS/README Bio-HTS/scripts Bio-HTS/t Bio-HTS/travisci \
           bioperl-ext/.??* bioperl-ext/Bio/SeqIO bioperl-ext/Bio/Tools bioperl-ext/Makefile.PL bioperl-ext/README* bioperl-ext/t bioperl-ext/examples \
           ensembl-vep/.??* ensembl-vep/docker \
           ensembl-xs/.??* ensembl-xs/TODO ensembl-xs/Changes ensembl-xs/INSTALL ensembl-xs/MANIFEST ensembl-xs/README ensembl-xs/t ensembl-xs/travisci \
           htslib/.??* htslib/INSTALL htslib/NEWS htslib/README* htslib/test && \
    # Only keep needed kent-335_base libraries for VEP - used by Bio::DB::BigFile (bigWig parsing)
    mv kent-335_base kent-335_base_bak && mkdir -p kent-335_base/src && \
    cp -R kent-335_base_bak/src/lib kent-335_base_bak/src/inc kent-335_base_bak/src/jkOwnLib kent-335_base/src/ && \
    cp kent-335_base_bak/src/*.sh kent-335_base/src/ && \
    rm -rf kent-335_base_bak

# Setup bioperl-ext
WORKDIR bioperl-ext/Bio/Ext/Align/
RUN perl -pi -e"s|(cd libs.+)CFLAGS=\\\'|\$1CFLAGS=\\\'-fPIC |" Makefile.PL

# Install htslib binaries (for 'bgzip' and 'tabix')
# htslib requires the packages 'zlib1g-dev', 'libbz2-dev' and 'liblzma-dev'
WORKDIR $HTSLIB_DIR
RUN make install && rm -f Makefile *.c

# Compile Variation LD C scripts
WORKDIR $OPT_SRC/var_c_code
RUN make && rm -f Makefile *.c


# Stage 2
FROM rocker/shiny:4.1.1
LABEL name="vcf-dart"

ENV OPT /opt/vep
USER shiny
COPY --chown=shiny:shiny --from=builder $OPT_SRC $OPT_SRC

USER root
ADD install.R /tmp/

RUN apt-get update && apt-get install -y \
  git \
  parallel \
  tabix \
  bedops \
  bcftools \
  vcftools \
  datamash \
  gawk \
  default-jre \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /home/miles/install && chown -R shiny:shiny /home/miles
WORKDIR /home/miles/install
USER shiny
RUN wget 'https://sourceforge.net/projects/snpeff/files/snpEff_latest_core.zip' && unzip snpEff_latest_core.zip && rm snpEff_latest_core.zip
USER root
RUN R -f /tmp/install.R

COPY server.R /srv/shiny-server/
COPY ui.R /srv/shiny-server/
COPY WESdiag_pipeline_dev.sh /data/

RUN mkdir -p /data && chown shiny:shiny /data
EXPOSE 3838