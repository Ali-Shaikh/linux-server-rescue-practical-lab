#!/usr/bin/env bash
set -Eeuo pipefail

bash /opt/lab/drills/fixtures/08-upstream-port.sh
systemctl enable rescue-upstream-port-check.service >/dev/null
