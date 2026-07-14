#!/usr/bin/env bash
set -Eeuo pipefail

systemctl enable rescue-cpu-hog.service >/dev/null
