ARG UBUNTU_VERSION=26.04
FROM ubuntu:${UBUNTU_VERSION}

ENV container=docker \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        bash ca-certificates curl dbus dnsutils iproute2 iputils-ping less \
        nano procps python3 sudo systemd systemd-sysv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker/common/rescue-web.py /opt/rescue-web/server.py
COPY docker/common/rescue-web.service /etc/systemd/system/rescue-web.service
COPY docker/common/configure-image.sh /tmp/configure-lab-image.sh
COPY checks/ /opt/lab/checks/
COPY drills/break/ /opt/lab/drills/break/
COPY drills/checks/ /opt/lab/drills/checks/

RUN bash /tmp/configure-lab-image.sh && rm /tmp/configure-lab-image.sh

VOLUME ["/var/lib/cloudsprocket-lab"]
EXPOSE 8080
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
