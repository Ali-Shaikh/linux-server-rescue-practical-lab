#!/usr/bin/env bash
set -Eeuo pipefail

systemctl enable rescue-data-volume.service >/dev/null
