#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="04-permission-denied"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly data_dir="/var/lib/rescue-web"

clean_fault() {
  chown rescue:rescue "${data_dir}"
  chmod 0750 "${data_dir}"
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

/opt/lab/drills/fixtures/04-permission-denied.sh
systemctl restart rescue-web.service >/dev/null 2>&1 || true

incident_visible=0
for _ in {1..20}; do
  if ! systemctl is-active --quiet rescue-web.service \
    && ! sudo -u rescue test -w "${data_dir}"; then
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
printf 'Incident 04 is active: rescue-web cannot write to its data directory.\n'
printf 'Open drills/04-permission-denied.md, then enter the host with lab shell.\n'
