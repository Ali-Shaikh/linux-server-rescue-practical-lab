#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="03-dns-ghost"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly wrong_address="203.0.113.99"
readonly upstream_name="rescue-api.internal"
readonly marker="cloudsprocket-dns-ghost"

clean_fault() {
  local temporary_file
  temporary_file="$(mktemp /run/rescue-hosts.XXXXXX)"
  awk -v marker="${marker}" 'index($0, marker) == 0' /etc/hosts > "${temporary_file}"
  cat "${temporary_file}" > /etc/hosts
  rm -f "${temporary_file}"
  systemctl stop rescue-upstream-check.service >/dev/null 2>&1 || true
  systemctl disable rescue-upstream-check.service >/dev/null 2>&1 || true
  systemctl reset-failed rescue-upstream-check.service >/dev/null 2>&1 || true
}

mkdir -p "${state_dir}"

if [[ -f "${active_file}" ]]; then
  active_drill="$(<"${active_file}")"
  if [[ "${active_drill}" == "${drill_id}" ]]; then
    printf 'Drill %s is already active. Its current state was not changed.\n' "${drill_id}"
    exit 0
  fi

  printf 'Cannot start %s while %s is active. Run lab reset first.\n' \
    "${drill_id}" "${active_drill}" >&2
  exit 1
fi

bash /opt/lab/drills/fixtures/03-dns-ghost.sh
systemctl enable rescue-upstream-check.service >/dev/null
systemctl restart rescue-upstream-check.service >/dev/null 2>&1 || true

resolved_address="$(getent ahostsv4 "${upstream_name}" | awk 'NR == 1 {print $1}')"
if [[ "${resolved_address}" != "${wrong_address}" ]] \
  || systemctl is-active --quiet rescue-upstream-check.service; then
  clean_fault
  printf 'The incident did not take effect. Run lab reset and try again.\n' >&2
  exit 1
fi

printf '%s\n' "${drill_id}" > "${active_file}"
printf 'Incident 03 is active: the rescue API upstream check is failing.\n'
printf 'Open drills/03-dns-ghost.md, then enter the host with lab shell.\n'
