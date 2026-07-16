#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="10-scheduled-regression"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"
readonly regression_timer="rescue-config-regression.timer"
readonly regression_service="rescue-config-regression.service"
readonly web_service="rescue-web.service"

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 10 with lab break 10.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

if systemctl is-active --quiet "${regression_timer}"; then
  printf 'NOT FIXED: the recurring configuration timer is still active.\n' >&2
  exit 1
fi

if systemctl is-enabled --quiet "${regression_timer}" 2>/dev/null; then
  printf 'NOT FIXED: the recurring configuration timer will return at the next boot.\n' >&2
  exit 1
fi

if systemctl is-active --quiet "${regression_service}"; then
  printf 'NOT FIXED: the recurring configuration job is still running.\n' >&2
  exit 1
fi

if ! systemctl is-enabled --quiet "${web_service}" \
  || ! systemctl is-active --quiet "${web_service}"; then
  printf 'NOT FIXED: rescue-web.service is not enabled and active.\n' >&2
  exit 1
fi

check_health() {
  local response
  response="$(curl --fail --silent --connect-timeout 1 --max-time 2 \
    http://127.0.0.1:8080/health 2>/dev/null || true)"
  [[ "${response}" == *'"service": "rescue-web"'* ]] \
    && ! curl --fail --silent --connect-timeout 1 --max-time 2 \
      http://127.0.0.1:8081/health >/dev/null 2>&1
}

if ! check_health; then
  printf 'NOT FIXED: rescue-web is not healthy exclusively on port 8080.\n' >&2
  exit 1
fi

sleep 4
if ! systemctl is-active --quiet "${web_service}" || ! check_health; then
  printf 'NOT FIXED: the bad configuration returned after the apparent repair.\n' >&2
  exit 1
fi

printf 'PASS: recurring automation is disabled and rescue-web remains healthy on port 8080.\n'
