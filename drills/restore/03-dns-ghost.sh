#!/usr/bin/env bash
set -Eeuo pipefail

bash /opt/lab/drills/fixtures/03-dns-ghost.sh
systemctl enable rescue-upstream-check.service >/dev/null
