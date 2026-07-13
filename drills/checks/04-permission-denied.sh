#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="04-permission-denied"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"
readonly data_dir="/var/lib/rescue-web"

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 04 with lab break 04.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

if ! sudo -u rescue test -w "${data_dir}"; then
  printf 'NOT FIXED: the rescue service account still cannot write to %s.\n' "${data_dir}" >&2
  exit 1
fi

service_user="$(systemctl show rescue-web.service --property=User --value)"
if [[ "${service_user}" != "rescue" ]]; then
  printf 'NOT FIXED: rescue-web.service now runs as %s instead of the rescue account.\n' \
    "${service_user:-an unspecified user}" >&2
  exit 1
fi

directory_mode="$(stat --format='%a' "${data_dir}")"
if (( (8#${directory_mode} & 8#002) != 0 )); then
  printf 'NOT FIXED: %s is world-writable; restore least-privilege access.\n' "${data_dir}" >&2
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
  printf 'NOT FIXED: rescue-web is active but its health endpoint does not answer.\n' >&2
  exit 1
fi

printf 'PASS: the service account can write its data and rescue-web is healthy.\n'
