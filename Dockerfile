FROM ubuntu:18.04 as dev_stage
LABEL org.opencontainers.image.source https://bitbucket.org/uprev/nrf5-docker.git

# Download tools and prerequisites
RUN apt-get update && apt-get install -y --no-install-recommends \ 
    curl\ 
    git \
    unzip \
    bzip2 \
    cmake \
    build-essential \
    gcc-multilib \
    srecord \
    pkg-config \
    python3 \
    python3-pip \
    python3-setuptools \
    libusb-1.0.0 && \
    apt-get clean all && rm -rf /var/lib/apt/lists/*

# # Download and install ARM toolchain matching the SDK
RUN curl -SL https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu-rm/9-2019q4/gcc-arm-none-eabi-9-2019-q4-major-x86_64-linux.tar.bz2 > /tmp/gcc-arm-none-eabi-9-2019-q4-major-linux.tar.bz2 && \
tar xvjf /tmp/gcc-arm-none-eabi-9-2019-q4-major-linux.tar.bz2 -C /usr/share && \
rm /tmp/gcc-arm-none-eabi-9-2019-q4-major-linux.tar.bz2

# Download NRF5 SDK v17.0.2 and extract nRF5 SDK to /nrf5/nRF5_SDK_17.0.2
RUN curl -SL https://developer.nordicsemi.com/nRF5_SDK/nRF5_SDK_v17.x.x/nRF5_SDK_17.0.2_d674dde.zip > /tmp/SDK_17.0.2.zip && \
mkdir -p /nrf && \
unzip -q /tmp/SDK_17.0.2.zip -d /nrf/ && \
mv /nrf/nRF5_SDK_17.0.2_d674dde /nrf/nRF5_SDK_17.0.2 && \
rm /tmp/SDK_17.0.2.zip

# Patch around what is likely to be an oversight in Nordic's SDK
# https://devzone.nordicsemi.com/f/nordic-q-a/68352/gcc-toolchain-version-for-sdk-17-0-2-on-posix
RUN \
echo "GNU_INSTALL_ROOT ?= /usr/share/gcc-arm-none-eabi-9-2019-q4-major/bin/" > /nrf/nRF5_SDK_17.0.2/components/toolchain/gcc/Makefile.posix && \
echo "GNU_VERSION ?= 9.2.1" >> /nrf/nRF5_SDK_17.0.2/components/toolchain/gcc/Makefile.posix && \
echo "GNU_PREFIX ?= arm-none-eabi" >> /nrf/nRF5_SDK_17.0.2/components/toolchain/gcc/Makefile.posix



# Install nRF Tools (makes it easy to build a DFU package) And mrtutils for mrt-ble
RUN pip3 install -U pip
RUN pip3 install nrfutil mrtutils 

ENV NRF_SDK_PATH /nrf/nRF5_SDK_17.0.2 
ENV PATH="/usr/share/gcc-arm-none-eabi-9-2019-q4-major/bin:${PATH}"

ARG DEV_PW=password
ARG ROOT_PW=password

# Add user dev to the image
RUN adduser --quiet dev && \
# Set password for the jenkins user (you may want to alter this).
    echo "dev:$DEV_PW" | chpasswd && \
    chown -R dev /home/dev 

RUN echo "root:$ROOT_PW" | chpasswd

# set gdbinit auto-load 
RUN echo "set auto-load safe-path /" >> /home/dev/.gdbinit


######################################################################################################
#                           Stage: jenkins                                                           #
######################################################################################################

FROM dev_stage as jenkins_stage

ARG JENKINS_PW=jenkins  
RUN apt-get update && apt-get install -y --no-install-recommends \ 
    openssh-server \
    openjdk-8-jdk  \
    openssh-server \
    ca-certificates \
    apt-get clean all && rm -rf /var/lib/apt/lists/*

RUN adduser --quiet jenkins && \
    echo "jenkins:$JENKINS_PW" | chpasswd && \
    mkdir /home/jenkins/.m2 && \
    mkdir /home/jenkins/jenkins && \
    chown -R jenkins /home/jenkins 


# Setup SSH server
RUN mkdir /var/run/sshd
RUN echo 'root:password' | chpasswd
RUN sed -i 's/#*PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config

# SSH login fix. Otherwise user is kicked off after login
RUN sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

ENV NOTVISIBLE="in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
