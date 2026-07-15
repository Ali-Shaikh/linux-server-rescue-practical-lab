#!/usr/bin/env bash
set -Eeuo pipefail

bash /opt/lab/drills/fixtures/09-port-conflict.sh
systemctl enable rescue-debug-listener.service >/dev/null
