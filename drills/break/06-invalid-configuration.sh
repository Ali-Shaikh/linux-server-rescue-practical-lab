#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="06-invalid-configuration"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly config_file="/etc/rescue-web/config.json"
readonly known_good="/etc/rescue-web/config.json.last-known-good"

clean_fault() {
  install -o root -g root -m 0644 "${known_good}" "${config_file}"
  systemctl reset-failed rescue-web.service >/dev/null 2>&1 || true
  systemctl restart rescue-web.service >/dev/null 2>&1 || true
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

/opt/lab/drills/fixtures/06-invalid-configuration.sh
systemctl restart rescue-web.service >/dev/null 2>&1 || true

incident_visible=0
for _ in {1..20}; do
  if ! python3 -m json.tool "${config_file}" >/dev/null 2>&1 \
    && ! systemctl is-active --quiet rescue-web.service; then
    incident_visible=1
    break
  fi
  sleep 0.25
done

if (( incident_visible == 0 )); then
  clean_fault
  printf 'The incident did not take effect. Run lab reset and try again.\n' >&2
  exit 1
fi

printf '%s\n' "${drill_id}" > "${active_file}"
printf 'Incident 06 is active: rescue-web cannot parse its deployed configuration.\n'
printf 'Open drills/06-invalid-configuration.md, then enter the host with lab shell.\n'
