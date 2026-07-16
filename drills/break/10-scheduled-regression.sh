#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="10-scheduled-regression"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly regression_dir="/var/lib/rescue-regression"
readonly deploy_script="/usr/local/bin/rescue-config-regression"
readonly regression_service="rescue-config-regression.service"
readonly regression_timer="rescue-config-regression.timer"
readonly service_file="/etc/systemd/system/${regression_service}"
readonly timer_file="/etc/systemd/system/${regression_timer}"
readonly config_file="/etc/rescue-web/config.json"
readonly known_good="${config_file}.last-known-good"
readonly web_service="rescue-web.service"
fault_started=0

clean_fault() {
  systemctl disable --now "${regression_timer}" >/dev/null 2>&1 || true
  systemctl stop "${regression_service}" >/dev/null 2>&1 || true
  rm -f "${deploy_script}" "${service_file}" "${timer_file}"
  rm -rf "${regression_dir}"
  systemctl daemon-reload >/dev/null 2>&1 || true
  install -o root -g root -m 0644 "${known_good}" "${config_file}"
  systemctl reset-failed "${regression_service}" "${web_service}" >/dev/null 2>&1 || true
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
bash /opt/lab/drills/fixtures/10-scheduled-regression.sh
systemctl daemon-reload
systemctl enable --now "${regression_timer}" >/dev/null
systemctl start "${regression_service}" >/dev/null

incident_visible=0
for _ in {1..30}; do
  response="$(curl --fail --silent --connect-timeout 1 --max-time 2 \
    http://127.0.0.1:8081/health 2>/dev/null || true)"
  if systemctl is-active --quiet "${regression_timer}" \
    && systemctl is-enabled --quiet "${regression_timer}" \
    && [[ "${response}" == *'"service": "rescue-web"'* ]] \
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
printf 'Incident 10 is active: scheduled automation keeps moving rescue-web to port 8081.\n'
printf 'Open drills/10-scheduled-regression.md, then enter the host with lab shell.\n'
