#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="03-dns-ghost"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"
readonly wrong_address="203.0.113.99"
readonly upstream_name="rescue-api.internal"

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 03 with lab break 03.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

resolved_address="$(getent ahostsv4 "${upstream_name}" | awk 'NR == 1 {print $1}')"
if [[ -z "${resolved_address}" || "${resolved_address}" == "${wrong_address}" ]]; then
  printf 'NOT FIXED: %s still resolves to %s through the host resolver.\n' \
    "${upstream_name}" "${resolved_address:-no IPv4 address}" >&2
  exit 1
fi

if ! systemctl is-active --quiet rescue-upstream-check.service; then
  printf 'NOT FIXED: rescue-upstream-check.service is not active. Inspect its status and journal.\n' >&2
  exit 1
fi

if ! curl --noproxy '*' --fail --silent --connect-timeout 1 --max-time 2 \
  "http://${upstream_name}:8080/health" >/dev/null; then
  printf 'NOT FIXED: the resolved upstream does not answer its health endpoint.\n' >&2
  exit 1
fi

printf 'PASS: %s resolves to the working upstream and its systemd check is active.\n' \
  "${upstream_name}"
