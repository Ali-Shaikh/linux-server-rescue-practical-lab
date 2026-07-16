#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="12-inode-exhaustion"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"
readonly data_dir="/var/lib/rescue-web"
readonly web_service="rescue-web.service"

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 12 with lab break 12.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

inode_percent="$(df -Pi "${data_dir}" | awk 'NR == 2 {print $5}')"
if [[ "${inode_percent}" == "100%" ]]; then
  printf 'NOT FIXED: the rescue-web filesystem still has no available inodes.\n' >&2
  exit 1
fi

probe="${data_dir}/.inode-write-probe"
if ! runuser --user rescue -- touch "${probe}" 2>/dev/null; then
  printf 'NOT FIXED: rescue-web still cannot create a file in its data directory.\n' >&2
  exit 1
fi
rm -f "${probe}"

if ! systemctl is-enabled --quiet "${web_service}" \
  || ! systemctl is-active --quiet "${web_service}"; then
  printf 'NOT FIXED: rescue-web.service is not enabled or not active.\n' >&2
  exit 1
fi

health_ready=0
for _ in {1..30}; do
  response="$(curl --fail --silent --connect-timeout 1 --max-time 2 \
    http://127.0.0.1:8080/health 2>/dev/null || true)"
  if [[ "${response}" == *'"service": "rescue-web"'* ]]; then
    health_ready=1
    break
  fi
  sleep 0.25
done

if (( health_ready == 0 )); then
  printf 'NOT FIXED: rescue-web does not answer on port 8080.\n' >&2
  exit 1
fi

printf 'PASS: filesystem inodes are available and rescue-web remains healthy.\n'
