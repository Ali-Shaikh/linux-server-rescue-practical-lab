ARG ROCKY_VERSION=10
FROM rockylinux/rockylinux:${ROCKY_VERSION}

ENV container=docker \
    LANG=C.UTF-8

RUN dnf install --assumeyes \
        bash bind-utils ca-certificates curl-minimal dbus-daemon findutils \
        iproute iputils less nano procps-ng python3 shadow-utils sudo systemd util-linux \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY docker/common/init-lab /usr/local/sbin/init-lab
COPY docker/common/configure-image.sh /tmp/configure-lab-image.sh

RUN bash /tmp/configure-lab-image.sh && rm /tmp/configure-lab-image.sh

VOLUME ["/var/lib/cloudsprocket-lab"]
EXPOSE 8080
STOPSIGNAL SIGRTMIN+3
CMD ["/usr/local/sbin/init-lab"]
