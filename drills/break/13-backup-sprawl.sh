#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="13-backup-sprawl"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly data_dir="/var/lib/rescue-web"
readonly backup_dir="${data_dir}/backups"
readonly fixture_state="/var/lib/rescue-backup"
readonly backup_script="/usr/local/bin/rescue-backup-run"
readonly volume_script="/usr/local/bin/rescue-backup-volume"
readonly volume_service="rescue-backup-volume.service"
readonly backup_service="rescue-backup.service"
readonly backup_timer="rescue-backup.timer"
readonly volume_file="/etc/systemd/system/${volume_service}"
readonly service_file="/etc/systemd/system/${backup_service}"
readonly timer_file="/etc/systemd/system/${backup_timer}"
readonly web_service="rescue-web.service"
fault_started=0

clean_fault() {
  systemctl disable --now "${backup_timer}" >/dev/null 2>&1 || true
  systemctl stop "${backup_service}" >/dev/null 2>&1 || true
  systemctl stop "${web_service}" >/dev/null 2>&1 || true
  systemctl disable --now "${volume_service}" >/dev/null 2>&1 || true
  mountpoint --quiet "${data_dir}" && umount "${data_dir}" || true
  rm -f "${backup_script}" "${volume_script}" \
    "${volume_file}" "${service_file}" "${timer_file}"
  rm -rf "${fixture_state}"
  systemctl daemon-reload >/dev/null 2>&1 || true
  install -d -o rescue -g rescue -m 0750 "${data_dir}"
  systemctl reset-failed "${volume_service}" "${backup_service}" \
    "${web_service}" >/dev/null 2>&1 || true
  systemctl restart "${web_service}" >/dev/null 2>&1 || true
}

cleanup_on_error() {
  local status=$?
  trap - ERR
  if (( fault_started == 1 )); then
    clean_fault
  fi
  exit "${status}"
}

trap cleanup_on_error ERR
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

if ! baseline="$(curl --fail --silent --connect-timeout 1 --max-time 2 \
  http://127.0.0.1:8080/health)" \
  || [[ "${baseline}" != *'"service": "rescue-web"'* ]]; then
  printf 'The healthy rescue-web baseline is unavailable. Run lab reset first.\n' >&2
  exit 1
fi

fault_started=1
bash /opt/lab/drills/fixtures/13-backup-sprawl.sh
systemctl daemon-reload
systemctl stop "${web_service}"
systemctl enable --now "${volume_service}" >/dev/null
systemctl reset-failed "${backup_service}" >/dev/null 2>&1 || true
systemctl enable --now "${backup_timer}" >/dev/null
systemctl reset-failed "${web_service}" >/dev/null 2>&1 || true
systemctl restart "${web_service}" >/dev/null 2>&1 || true

incident_visible=0
for _ in {1..40}; do
  used_percent="$(df -P "${data_dir}" | awk 'NR == 2 {print $5}')"
  complete_count="$(find "${backup_dir}" -xdev -maxdepth 1 -type f \
    -name 'backup-*.tar' | wc -l)"
  partial_file="$(find "${backup_dir}" -xdev -maxdepth 1 -type f \
    -name '.backup-*.tar.partial' -print -quit)"
  if systemctl is-active --quiet "${backup_timer}" \
    && systemctl is-enabled --quiet "${backup_timer}" \
    && [[ "${used_percent}" == "100%" ]] \
    && (( complete_count >= 2 )) \
    && [[ -n "${partial_file}" ]] \
    && ! curl --fail --silent --connect-timeout 1 --max-time 2 \
      http://127.0.0.1:8080/health >/dev/null 2>&1; then
    incident_visible=1
    break
  fi
  sleep 0.25
done

if (( incident_visible == 0 )); then
  clean_fault
  fault_started=0
  printf 'The incident did not take effect. Run lab reset and try again.\n' >&2
  exit 1
fi

printf '%s\n' "${drill_id}" > "${active_file}"
fault_started=0
trap - ERR
printf 'Incident 13 is active: recurring backups fill the rescue-web filesystem.\n'
printf 'Open drills/13-backup-sprawl.md, then enter the host with lab shell.\n'
