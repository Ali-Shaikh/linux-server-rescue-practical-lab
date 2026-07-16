#!/usr/bin/env bash
set -Eeuo pipefail

bash /opt/lab/drills/fixtures/12-inode-exhaustion.sh
# init-lab runs restore scripts before it execs systemd as PID 1. Enabling the
# unit here makes multi-user.target prepare the fault before rescue-web starts;
# daemon-reload and --now require a running manager and do not belong here.
systemctl enable rescue-inode-volume.service >/dev/null
