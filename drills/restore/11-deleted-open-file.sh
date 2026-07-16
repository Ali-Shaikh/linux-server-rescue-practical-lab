#!/usr/bin/env bash
set -Eeuo pipefail

bash /opt/lab/drills/fixtures/11-deleted-open-file.sh
# init-lab runs restore scripts before it execs systemd as PID 1. Enabling the
# units here makes multi-user.target start them in dependency order at boot;
# daemon-reload and --now require a running manager and do not belong here.
systemctl enable rescue-deleted-log-volume.service >/dev/null
systemctl enable rescue-deleted-log-holder.service >/dev/null
