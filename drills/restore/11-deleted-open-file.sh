#!/usr/bin/env bash
set -Eeuo pipefail

bash /opt/lab/drills/fixtures/11-deleted-open-file.sh
systemctl enable rescue-deleted-log-volume.service >/dev/null
systemctl enable rescue-deleted-log-holder.service >/dev/null
