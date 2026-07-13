#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="05-runaway-process"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly unit="rescue-cpu-hog.service"

clean_fault() {
  systemctl disable --now "${unit}" >/dev/null 2>&1 || true
  systemctl reset-failed "${unit}" >/dev/null 2>&1 || true
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

if ! systemctl enable --now "${unit}" >/dev/null; then
  clean_fault
  printf 'The bounded worker could not be started. Run lab reset and try again.\n' >&2
  exit 1
fi

incident_visible=0
for _ in {1..20}; do
  main_pid="$(systemctl show "${unit}" --property=MainPID --value)"
  if systemctl is-active --quiet "${unit}" \
    && [[ "${main_pid}" =~ ^[1-9][0-9]*$ ]] \
    && [[ -r "/proc/${main_pid}/stat" ]]; then
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
printf 'Incident 05 is active: a restart-managed worker is consuming CPU.\n'
printf 'Open drills/05-runaway-process.md, then enter the host with lab shell.\n'
