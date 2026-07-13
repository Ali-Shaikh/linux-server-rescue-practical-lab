#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="02-full-filesystem"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 02 with lab break 02.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

if ! systemctl is-active --quiet rescue-web.service; then
  printf 'NOT FIXED: rescue-web.service is not active. Inspect its journal and application filesystem.\n' >&2
  exit 1
fi

if ! curl --fail --silent http://127.0.0.1:8080/health >/dev/null; then
  printf 'NOT FIXED: systemd reports active, but the health endpoint does not answer.\n' >&2
  exit 1
fi

printf 'PASS: rescue-web can write its startup state and answers on port 8080.\n'
