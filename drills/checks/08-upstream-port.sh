#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="08-upstream-port"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"
readonly config_file="/etc/rescue-upstream-port.conf"
readonly service="rescue-upstream-port-check.service"

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 08 with lab break 08.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

mapfile -t settings < <(grep -E '^UPSTREAM_URL=' "${config_file}" 2>/dev/null || true)
if (( ${#settings[@]} != 1 )); then
  printf 'NOT FIXED: %s must contain exactly one UPSTREAM_URL setting.\n' \
    "${config_file}" >&2
  exit 1
fi

upstream_url="${settings[0]#UPSTREAM_URL=}"
if [[ ! "${upstream_url}" =~ ^http://[a-zA-Z0-9][a-zA-Z0-9.-]*:[0-9]{1,5}/[a-zA-Z0-9._/-]+$ ]]; then
  printf 'NOT FIXED: UPSTREAM_URL is not a supported internal HTTP URL.\n' >&2
  exit 1
fi

if ! systemctl is-enabled --quiet "${service}" \
  || ! systemctl is-active --quiet "${service}"; then
  printf 'NOT FIXED: %s is not enabled and active.\n' "${service}" >&2
  exit 1
fi

if ! response="$(curl --noproxy '*' --fail --silent --show-error \
  --connect-timeout 1 --max-time 2 "${upstream_url}")"; then
  printf 'NOT FIXED: the configured upstream health endpoint is unavailable.\n' >&2
  exit 1
fi

if [[ "${response}" != *'"service":"upstream-api"'* \
  || "${response}" != *'"status":"ok"'* ]]; then
  printf 'NOT FIXED: the configured endpoint is not the healthy upstream API.\n' >&2
  exit 1
fi

printf 'PASS: the systemd probe reaches the healthy external upstream API.\n'
