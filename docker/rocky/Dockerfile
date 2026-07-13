ARG ROCKY_VERSION=10
FROM rockylinux/rockylinux:${ROCKY_VERSION}

ENV container=docker \
    LANG=C.UTF-8

RUN dnf install --assumeyes \
        bash bind-utils ca-certificates curl-minimal dbus-daemon findutils \
        iproute iputils less nano procps-ng python3 shadow-utils sudo systemd \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY docker/common/rescue-web.py /opt/rescue-web/server.py
COPY docker/common/rescue-web.service /etc/systemd/system/rescue-web.service
COPY docker/common/rescue-data-volume.service /etc/systemd/system/rescue-data-volume.service
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
