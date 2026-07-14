#!/usr/bin/env bash
set -Eeuo pipefail

if ! id --user rescue >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash rescue
fi

install -d -m 0755 /etc/sudoers.d /var/lib/cloudsprocket-lab
# Unrestricted sudo is intentional: learners need root in this disposable lab host.
printf 'rescue ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/rescue
chmod 0440 /etc/sudoers.d/rescue
chmod 0755 /usr/local/sbin/init-lab
systemctl set-default multi-user.target
