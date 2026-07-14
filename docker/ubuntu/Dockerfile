ARG UBUNTU_VERSION=26.04
FROM ubuntu:${UBUNTU_VERSION}

ENV container=docker \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        bash ca-certificates curl dbus dnsutils iproute2 iputils-ping less \
        nano procps python3 sudo systemd systemd-sysv util-linux \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker/common/init-lab /usr/local/sbin/init-lab
COPY docker/common/configure-image.sh /tmp/configure-lab-image.sh

RUN bash /tmp/configure-lab-image.sh && rm /tmp/configure-lab-image.sh

VOLUME ["/var/lib/cloudsprocket-lab"]
EXPOSE 8080
STOPSIGNAL SIGRTMIN+3
CMD ["/usr/local/sbin/init-lab"]
