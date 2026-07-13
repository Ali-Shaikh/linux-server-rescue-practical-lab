#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="05-runaway-process"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"
readonly unit="rescue-cpu-hog.service"

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 05 with lab break 05.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

if systemctl is-active --quiet "${unit}"; then
  printf 'NOT FIXED: %s is still active and consuming CPU.\n' "${unit}" >&2
  exit 1
fi

if systemctl is-enabled --quiet "${unit}"; then
  printf 'NOT FIXED: %s is stopped but still enabled for the next boot.\n' "${unit}" >&2
  exit 1
fi

if ! systemctl is-active --quiet rescue-web.service \
  || ! curl --fail --silent http://127.0.0.1:8080/health >/dev/null; then
  printf 'NOT FIXED: the unwanted worker is gone, but rescue-web is not healthy.\n' >&2
  exit 1
fi

printf 'PASS: the runaway worker is stopped, disabled and rescue-web remains healthy.\n'
