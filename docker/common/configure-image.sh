#!/usr/bin/env bash
set -Eeuo pipefail

if ! id --user rescue >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash rescue
fi

install -d -m 0755 /etc/sudoers.d /var/lib/cloudsprocket-lab
printf 'rescue ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/rescue
chmod 0440 /etc/sudoers.d/rescue
chmod 0755 /opt/rescue-web/server.py
chmod 0644 /etc/systemd/system/rescue-web.service

find /opt/lab/checks /opt/lab/drills/break /opt/lab/drills/checks \
  -type f -name '*.sh' -exec chmod 0755 {} +

systemctl enable rescue-web.service
systemctl set-default multi-user.target
