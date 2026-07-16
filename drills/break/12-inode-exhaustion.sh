#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="12-inode-exhaustion"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly data_dir="/var/lib/rescue-web"
readonly sessions_dir="${data_dir}/sessions"
readonly volume_script="/usr/local/bin/rescue-inode-volume"
readonly volume_service="rescue-inode-volume.service"
readonly volume_file="/etc/systemd/system/${volume_service}"
readonly web_service="rescue-web.service"
fault_started=0

clean_fault() {
  systemctl stop "${web_service}" >/dev/null 2>&1 || true
  systemctl disable --now "${volume_service}" >/dev/null 2>&1 || true
  mountpoint --quiet "${data_dir}" && umount "${data_dir}" || true
  rm -f "${volume_script}" "${volume_file}"
  systemctl daemon-reload >/dev/null 2>&1 || true
  install -d -o rescue -g rescue -m 0750 "${data_dir}"
  systemctl reset-failed "${volume_service}" "${web_service}" \
    >/dev/null 2>&1 || true
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
bash /opt/lab/drills/fixtures/12-inode-exhaustion.sh
systemctl daemon-reload
systemctl stop "${web_service}"
systemctl enable --now "${volume_service}" >/dev/null
systemctl reset-failed "${web_service}" >/dev/null 2>&1 || true
systemctl restart "${web_service}" >/dev/null 2>&1 || true

incident_visible=0
for _ in {1..40}; do
  inode_percent="$(df -Pi "${data_dir}" | awk 'NR == 2 {print $5}')"
  block_percent="$(df -P "${data_dir}" | awk 'NR == 2 {print $5}')"
  if systemctl is-active --quiet "${volume_service}" \
    && systemctl is-enabled --quiet "${volume_service}" \
    && [[ "${inode_percent}" == "100%" ]] \
    && [[ "${block_percent}" != "100%" ]] \
    && find "${sessions_dir}" -xdev -type f -name 'stale-*.session' -print -quit \
      | grep --quiet . \
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
printf 'Incident 12 is active: rescue-web has no available filesystem inodes.\n'
printf 'Open drills/12-inode-exhaustion.md, then enter the host with lab shell.\n'
