ARG DEBIAN_VERSION=13
FROM debian:${DEBIAN_VERSION}

ENV container=docker \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        bash ca-certificates curl dbus dnsutils iproute2 iputils-ping less \
        nano procps python3 sudo systemd systemd-sysv util-linux \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker/common/rescue-web.py /opt/rescue-web/server.py
COPY docker/common/rescue-web.service /etc/systemd/system/rescue-web.service
COPY docker/common/rescue-web-config.json /etc/rescue-web/config.json
COPY docker/common/rescue-web-config.json /etc/rescue-web/config.json.last-known-good
COPY docker/common/rescue-data-volume.service /etc/systemd/system/rescue-data-volume.service
COPY docker/common/rescue-cpu-hog /usr/local/bin/rescue-cpu-hog
COPY docker/common/rescue-cpu-hog.service /etc/systemd/system/rescue-cpu-hog.service
COPY docker/common/rescue-upstream-check /usr/local/bin/rescue-upstream-check
COPY docker/common/rescue-upstream-check.service /etc/systemd/system/rescue-upstream-check.service
COPY docker/common/init-lab /usr/local/sbin/init-lab
COPY docker/common/configure-image.sh /tmp/configure-lab-image.sh
COPY checks/ /opt/lab/checks/
COPY drills/break/ /opt/lab/drills/break/
COPY drills/checks/ /opt/lab/drills/checks/
COPY drills/fixtures/ /opt/lab/drills/fixtures/

RUN bash /tmp/configure-lab-image.sh && rm /tmp/configure-lab-image.sh

VOLUME ["/var/lib/cloudsprocket-lab"]
EXPOSE 8080
STOPSIGNAL SIGRTMIN+3
CMD ["/usr/local/sbin/init-lab"]
