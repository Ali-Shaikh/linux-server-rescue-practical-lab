#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="09-port-conflict"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"
readonly rogue_service="rescue-debug-listener.service"
readonly web_service="rescue-web.service"

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 09 with lab break 09.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

if systemctl is-active --quiet "${rogue_service}"; then
  printf 'NOT FIXED: the unauthorised debug listener is still active.\n' >&2
  exit 1
fi

if systemctl is-enabled --quiet "${rogue_service}" 2>/dev/null; then
  printf 'NOT FIXED: the unauthorised debug listener will return at the next boot.\n' >&2
  exit 1
fi

if ! systemctl is-enabled --quiet "${web_service}" \
  || ! systemctl is-active --quiet "${web_service}"; then
  printf 'NOT FIXED: rescue-web.service is not enabled and active.\n' >&2
  exit 1
fi

if ! response="$(curl --fail --silent --connect-timeout 1 --max-time 2 \
  http://127.0.0.1:8080/health)" \
  || [[ "${response}" != *'"service": "rescue-web"'* ]]; then
  printf 'NOT FIXED: port 8080 does not return the rescue-web health response.\n' >&2
  exit 1
fi

main_pid="$(systemctl show --property MainPID --value "${web_service}")"
listener="$(ss -H -ltnp '( sport = :8080 )')"
if [[ ! "${main_pid}" =~ ^[1-9][0-9]*$ ]] \
  || [[ "${listener}" != *"pid=${main_pid},"* ]]; then
  printf 'NOT FIXED: rescue-web does not own the port 8080 listening socket.\n' >&2
  exit 1
fi

printf 'PASS: rescue-web owns port 8080 and the unauthorised listener cannot return.\n'
