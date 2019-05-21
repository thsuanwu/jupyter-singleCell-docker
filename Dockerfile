# adapted from https://github.com/DataBiosphere/leonardo/blob/develop/docker/jupyter/Dockerfile

FROM ubuntu:bionic

USER root

#######################
# Prerequisites
#######################

ENV DEBIAN_FRONTEND noninteractive
ENV CRAN_REPO "deb https://cloud.r-project.org/bin/linux/ubuntu bionic-cran35/"
ENV BACKPORTS_REPO "deb http://mirror.math.princeton.edu/pub/ubuntu bionic-backports main restricted universe"
#ENV CRAN_REPO http://cran.mtu.edu

RUN echo $BACKPORTS_REPO >> /etc/apt/sources.list \
 && apt-get update \
 && apt-get -yq dist-upgrade \
 && apt-get install -yq --no-install-recommends \
    nano \
    sudo \
    gnupg \
    dirmngr \
    wget \
    ca-certificates \
    curl \
    build-essential \
    autoconf \
    lsb-release \
    procps \
    openssl \
    make \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    llvm \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    # to support userScript pip installs via git
    git \
    locales \
    jq \
    libigraph-dev \
    libxml2-dev \
    cmake \

 # R separately because it depends on gnupg installed above
 && echo $CRAN_REPO >> /etc/apt/sources.list \
 && sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9 \

 # Uncomment en_US.UTF-8 for inclusion in generation
 && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
 # Generate locale
 && locale-gen \

 # google-cloud-sdk separately because it need lsb-release and other prereqs installed above
 && export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)" \
 && echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" > /etc/apt/sources.list.d/google-cloud-sdk.list \
 && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
 && apt-get update \
 && apt-get install -yq --no-install-recommends \
    google-cloud-sdk \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

ENV LC_ALL en_US.UTF-8

#######################
# Java
#######################

ENV JAVA_VER jdk1.8.0_131
ENV JAVA_TGZ jdk-8u131-linux-x64.tar.gz
ENV JAVA_URL http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/$JAVA_TGZ
ENV JAVA_HOME /usr/lib/jdk/$JAVA_VER

RUN wget --header "Cookie: oraclelicense=accept-securebackup-cookie" $JAVA_URL \
 && mkdir -p /usr/lib/jdk && tar -zxf $JAVA_TGZ -C /usr/lib/jdk \
 && update-alternatives --install /usr/bin/java java $JAVA_HOME/bin/java 100 \
 && update-alternatives --install /usr/bin/javac javac $JAVA_HOME/bin/javac 100 \
 && rm $JAVA_TGZ

##############################
# Spark / Hadoop / Hive / Hail
##############################

# Use Spark 2.2.0 which corresponds to Dataproc 1.2. See:
#   https://cloud.google.com/dataproc/docs/concepts/versioning/dataproc-versions
# Note: we are actually using Spark 2.2.1, but the Hail package is built using 2.2.0
ENV SPARK_VER 2.2.0
ENV SPARK_HOME=/usr/lib/spark

# result of `gsutil cat gs://hail-common/builds/0.2/latest-hash/cloudtools-3-spark-2.2.0.txt` on 26 March 2019
ENV HAILHASH daed180b84d8
ENV HAILJAR hail-0.2-$HAILHASH-Spark-$SPARK_VER.jar
ENV HAILPYTHON hail-0.2-$HAILHASH.zip
ENV HAIL_HOME /etc/hail
ENV KERNELSPEC_HOME /usr/local/share/jupyter/kernels

# Note Spark and Hadoop are mounted from the outside Dataproc VM.
# Make empty conf dirs for the update-alternatives commands.
RUN mkdir -p /etc/spark/conf.dist && mkdir -p /etc/hadoop/conf.empty && mkdir -p /etc/hive/conf.dist \
 && update-alternatives --install /etc/spark/conf spark-conf /etc/spark/conf.dist 100 \
 && update-alternatives --install /etc/hadoop/conf hadoop-conf /etc/hadoop/conf.empty 100 \
 && update-alternatives --install /etc/hive/conf hive-conf /etc/hive/conf.dist 100 \
 && mkdir $HAIL_HOME && cd $HAIL_HOME \
 && wget -nv http://storage.googleapis.com/hail-common/builds/0.2/jars/$HAILJAR \
 && wget -nv http://storage.googleapis.com/hail-common/builds/0.2/python/$HAILPYTHON \
 && cd -

#######################
# Python / Jupyter
#######################

ENV USER jupyter-user
ENV UID 1000
ENV HOME /home/$USER

# ensure this matches c.NotebookApp.port in jupyter_notebook_config.py
ENV JUPYTER_PORT 8000
ENV JUPYTER_HOME /etc/jupyter
ENV PYSPARK_DRIVER_PYTHON jupyter
ENV PYSPARK_DRIVER_PYTHON_OPTS notebook

ENV PATH $SPARK_HOME:$SPARK_HOME/python:$SPARK_HOME/bin:$HAIL_HOME:$PATH
ENV PYTHONPATH $PYTHONPATH:$HAIL_HOME/$HAILPYTHON:$HAIL_HOME/python:$SPARK_HOME/python:$JUPYTER_HOME/custom

RUN apt-get update \
 && apt-get install -yq --no-install-recommends \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    liblzo2-dev \
    python-tk \
    liblzo2-dev \
    libz-dev \

 # NOTE! not sure why, but this must run before pip installation
 && useradd -m -s /bin/bash -N -G sudo -u $UID $USER \
 && echo "$USER:ubuntu" | chpasswd

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 19.0.1

RUN apt-get update \
 && curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash - \
 && apt-get install \
    # for jupyterlab extensions
    nodejs \

 && pip3 install tornado==4.5.3 \
 && pip3 install -U decorator \
 && pip3 install parsimonious \
# # python 3 packages
 && pip3 install py4j \
 && pip3 install numpy \
 && pip3 install scipy==1.2.0 \
 && pip3 install scikit-learn==0.20.3 \
 && pip3 install matplotlib \
 && pip3 install pandas \
 && pip3 install seaborn \
 && pip3 install jupyter \
 && pip3 install jupyterlab \
 && pip3 install python-lzo \
 && pip3 install google-api-core==1.5.0 \
 && pip3 install google-cloud-bigquery==1.7.0 \
 && pip3 install google-cloud-bigquery-datatransfer==0.1.1 \
 && pip3 install google-cloud-core==0.28.1 \
 && pip3 install google-cloud-datastore==1.7.0 \
 && pip3 install google-cloud-resource-manager==0.28.1 \
 && pip3 install google-cloud-storage==1.13.0 \
 && pip3 install --ignore-installed firecloud==0.16.18 \
 && pip3 install scikit-learn \
 && pip3 install statsmodels \
 && pip3 install bokeh \
 && pip3 install plotnine \
 && pip3 install pyfasta \
 && pip3 install pdoc \
 && pip3 install biopython \
 && pip3 install bx-python \
 && pip3 install fastinterval \
 && pip3 install matplotlib-venn \
 # for jupyter_localize_extension
 && pip3 install python-datauri \
 && pip3 install jupyter_contrib_nbextensions \
 && pip3 install jupyter_nbextensions_configurator \
 && pip3 install cookiecutter \
 && pip3 install 'scanpy[louvain,leiden,bbknn]' \
 && pip3 install fa2 mnnpy MulticoreTSNE plotly \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# make pip install to a user directory, instead of a system directory which requires root.
# this is useful so `pip install` commands can be run in the context of a notebook.
ENV PIP_USER=true

#######################
# R Kernel
#######################

RUN apt-get update && apt-get install -y --no-install-recommends apt-utils libcurl4 libcurl4-openssl-dev libssl-dev fonts-dejavu tzdata \
 && apt-get update && apt-get -t bionic-cran35 install -y --no-install-recommends \
    r-base-core \
    r-base \
    r-base-dev \
    r-recommended \
    r-cran-mgcv \
    r-cran-codetools \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 # fixes broken gfortan dependency needed by some R libraries
 # see: https://github.com/DataBiosphere/leonardo/issues/710
 && ln -s /usr/lib/x86_64-linux-gnu/libgfortran.so.3 /usr/lib/x86_64-linux-gnu/libgfortran.so

RUN R -e 'install.packages(c( \
    "IRdisplay",  \
    "evaluate",  \
    "pbdZMQ",  \
    "devtools",  \
    "uuid",  \
    "reshape2",  \
    "bigrquery",  \
    "googleCloudStorageR",  \
    "BiocManager", \
    "Seurat", \
    "tidyverse"), \
    repos="http://cran.mtu.edu")' \
 && R -e 'devtools::install_github("DataBiosphere/Ronaldo")'

RUN R -e 'BiocManager::install()'  \
 && R -e 'BiocManager::install(c("GenomicFeatures", "AnnotationDbi", "scran", "scater"))' \

RUN R -e 'devtools::install_github("IRkernel/IRkernel")' \
 && R -e 'IRkernel::installspec(user=FALSE)' \
 && chown -R $USER:users /home/jupyter-user  \
 && R -e 'devtools::install_github("apache/spark@v2.2.3", subdir="R/pkg")' \
 && mkdir -p /home/jupyter-user/.rpackages \
 && echo "R_LIBS=/home/jupyter-user/.rpackages" > /home/jupyter-user/.Renviron \
 && chown -R $USER:users /home/jupyter-user/.rpackages

#######################
# Utilities
#######################

# Ubuntu python path is /usr/bin
RUN ln -sf /usr/bin/python3 /usr/local/bin/python
RUN ln -sf /usr/bin/python3 /usr/local/bin/python3

ADD scripts $JUPYTER_HOME/scripts
ADD custom/jupyter_delocalize.py $JUPYTER_HOME/custom/
ADD custom/jupyter_localize_extension.py $JUPYTER_HOME/custom/

RUN chown -R $USER:users $JUPYTER_HOME \
 && find $JUPYTER_HOME/scripts -name '*.sh' -type f | xargs chmod +x \
 && chown -R $USER:users /usr/local/share/jupyter/lab

USER $USER
WORKDIR $HOME

EXPOSE $JUPYTER_PORT
ENTRYPOINT ["/usr/local/bin/jupyter", "notebook"]
