#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="11-deleted-open-file"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"
readonly data_dir="/var/lib/rescue-web"
readonly deleted_log="${data_dir}/archived-access.log (deleted)"
readonly holder_service="rescue-deleted-log-holder.service"
readonly web_service="rescue-web.service"

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 11 with lab break 11.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

if systemctl is-active --quiet "${holder_service}"; then
  printf 'NOT FIXED: the process retaining the deleted log is still active.\n' >&2
  exit 1
fi

if systemctl is-enabled --quiet "${holder_service}" 2>/dev/null; then
  printf 'NOT FIXED: the deleted-log holder will return at the next boot.\n' >&2
  exit 1
fi

deleted_fd="$(find /proc/[0-9]*/fd -maxdepth 1 -lname "${deleted_log}" \
  -print -quit 2>/dev/null || true)"
if [[ -n "${deleted_fd}" ]]; then
  printf 'NOT FIXED: %s still retains the deleted log.\n' "${deleted_fd}" >&2
  exit 1
fi

used_percent="$(df -P "${data_dir}" | awk 'NR == 2 {print $5}')"
if [[ "${used_percent}" == "100%" ]]; then
  printf 'NOT FIXED: the rescue-web filesystem is still full.\n' >&2
  exit 1
fi

if ! systemctl is-enabled --quiet "${web_service}" \
  || ! systemctl is-active --quiet "${web_service}"; then
  printf 'NOT FIXED: rescue-web.service is not enabled and active.\n' >&2
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

printf 'PASS: the deleted log is released and rescue-web remains healthy.\n'
