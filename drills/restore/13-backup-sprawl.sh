#!/usr/bin/env bash
set -Eeuo pipefail

bash /opt/lab/drills/fixtures/13-backup-sprawl.sh
# init-lab runs restore scripts before it execs systemd as PID 1. Enabling the
# volume and timer here lets their declared ordering restore the full backup
# filesystem before rescue-web starts.
systemctl enable rescue-backup-volume.service >/dev/null
systemctl enable rescue-backup.timer >/dev/null
