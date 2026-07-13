#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="06-invalid-configuration"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"
readonly config_file="/etc/rescue-web/config.json"

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 06 with lab break 06.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

if ! python3 -m json.tool "${config_file}" >/dev/null 2>&1; then
  printf 'NOT FIXED: %s is still not valid JSON.\n' "${config_file}" >&2
  exit 1
fi

if ! systemctl is-active --quiet rescue-web.service; then
  printf 'NOT FIXED: rescue-web.service is not active. Inspect its status and journal.\n' >&2
  exit 1
fi

health_ready=0
for _ in {1..20}; do
  if curl --fail --silent http://127.0.0.1:8080/health >/dev/null 2>&1; then
    health_ready=1
    break
  fi
  sleep 0.25
done

if (( health_ready == 0 )); then
  printf 'NOT FIXED: the repaired configuration does not produce a healthy service.\n' >&2
  exit 1
fi

printf 'PASS: the deployed configuration is valid and rescue-web is healthy.\n'
