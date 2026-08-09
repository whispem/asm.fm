FROM --platform=linux/amd64 ubuntu:24.04

RUN apt-get update && \
    apt-get install -y nasm binutils make alsa-utils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /asmfm

CMD ["/bin/bash"]