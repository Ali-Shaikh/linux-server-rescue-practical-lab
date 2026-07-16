#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="11-deleted-open-file"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly data_dir="/var/lib/rescue-web"
readonly deleted_log="${data_dir}/archived-access.log (deleted)"
readonly fixture_state="/var/lib/rescue-deleted-log"
readonly volume_script="/usr/local/bin/rescue-deleted-log-volume"
readonly holder_script="/usr/local/bin/rescue-deleted-log-holder"
readonly volume_service="rescue-deleted-log-volume.service"
readonly holder_service="rescue-deleted-log-holder.service"
readonly volume_file="/etc/systemd/system/${volume_service}"
readonly holder_file="/etc/systemd/system/${holder_service}"
readonly web_service="rescue-web.service"
fault_started=0

clean_fault() {
  systemctl disable --now "${holder_service}" >/dev/null 2>&1 || true
  systemctl stop "${web_service}" >/dev/null 2>&1 || true
  systemctl disable --now "${volume_service}" >/dev/null 2>&1 || true
  mountpoint --quiet "${data_dir}" && umount "${data_dir}" || true
  rm -f "${volume_script}" "${holder_script}" "${volume_file}" "${holder_file}"
  rm -rf "${fixture_state}" /run/rescue-deleted-log
  systemctl daemon-reload >/dev/null 2>&1 || true
  install -d -o rescue -g rescue -m 0750 "${data_dir}"
  systemctl reset-failed "${holder_service}" "${volume_service}" \
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
bash /opt/lab/drills/fixtures/11-deleted-open-file.sh
systemctl daemon-reload
systemctl stop "${web_service}"
systemctl enable --now "${volume_service}" >/dev/null
systemctl enable --now "${holder_service}" >/dev/null
systemctl reset-failed "${web_service}" >/dev/null 2>&1 || true
systemctl restart "${web_service}" >/dev/null 2>&1 || true

incident_visible=0
for _ in {1..40}; do
  holder_pid="$(systemctl show --property MainPID --value "${holder_service}")"
  deleted_fd=""
  if [[ "${holder_pid}" =~ ^[1-9][0-9]*$ ]]; then
    deleted_fd="$(find "/proc/${holder_pid}/fd" -maxdepth 1 \
      -lname "${deleted_log}" -print -quit 2>/dev/null || true)"
  fi
  used_percent="$(df -P "${data_dir}" | awk 'NR == 2 {print $5}')"
  if systemctl is-active --quiet "${holder_service}" \
    && systemctl is-enabled --quiet "${holder_service}" \
    && [[ -f /run/rescue-deleted-log/ready ]] \
    && [[ -n "${deleted_fd}" ]] \
    && [[ "${used_percent}" == "100%" ]] \
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
printf 'Incident 11 is active: missing log bytes fill the rescue-web filesystem.\n'
printf 'Open drills/11-deleted-open-file.md, then enter the host with lab shell.\n'
