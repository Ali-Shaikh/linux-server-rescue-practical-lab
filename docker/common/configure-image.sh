#!/usr/bin/env bash
set -Eeuo pipefail

if ! id --user rescue >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash rescue
fi

install -d -m 0755 /etc/sudoers.d /var/lib/cloudsprocket-lab
install -d -o rescue -g rescue -m 0750 /var/lib/rescue-web
# Unrestricted sudo is intentional: learners need root in this disposable lab host.
printf 'rescue ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/rescue
chmod 0440 /etc/sudoers.d/rescue
chmod 0755 /opt/rescue-web/server.py
chmod 0755 /usr/local/sbin/init-lab
chmod 0644 /etc/systemd/system/rescue-web.service \
  /etc/systemd/system/rescue-data-volume.service

find /opt/lab/checks /opt/lab/drills/break /opt/lab/drills/checks \
  /opt/lab/drills/fixtures \
  -type f -name '*.sh' -exec chmod 0755 {} +

systemctl enable rescue-web.service
systemctl set-default multi-user.target
