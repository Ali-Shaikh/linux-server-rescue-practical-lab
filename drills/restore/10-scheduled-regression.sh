#!/usr/bin/env bash
set -Eeuo pipefail

bash /opt/lab/drills/fixtures/10-scheduled-regression.sh
systemctl enable rescue-config-regression.timer >/dev/null
