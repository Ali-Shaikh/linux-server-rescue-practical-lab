#!/usr/bin/env bash
set -Eeuo pipefail

readonly data_dir="/var/lib/rescue-web"

mkdir -p "${data_dir}"
chown root:root "${data_dir}"
chmod 0750 "${data_dir}"
