#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="09-port-conflict"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly rogue_service="rescue-debug-listener.service"
readonly web_service="rescue-web.service"
readonly unit_file="/etc/systemd/system/${rogue_service}"
readonly content_dir="/var/lib/rescue-debug"

clean_fault() {
  systemctl disable --now "${rogue_service}" >/dev/null 2>&1 || true
  rm -f "${unit_file}"
  rm -rf "${content_dir}"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed "${rogue_service}" "${web_service}" >/dev/null 2>&1 || true
  systemctl restart "${web_service}" >/dev/null 2>&1 || true
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

if ! baseline="$(curl --fail --silent --connect-timeout 1 --max-time 2 \
  http://127.0.0.1:8080/health)" \
  || [[ "${baseline}" != *'"service": "rescue-web"'* ]]; then
  printf 'The healthy rescue-web baseline is unavailable. Run lab reset first.\n' >&2
  exit 1
fi

bash /opt/lab/drills/fixtures/09-port-conflict.sh
systemctl daemon-reload
systemctl stop "${web_service}"
systemctl enable --now "${rogue_service}" >/dev/null
systemctl reset-failed "${web_service}" >/dev/null 2>&1 || true
systemctl start "${web_service}" >/dev/null 2>&1 || true

incident_visible=0
for _ in {1..20}; do
  response="$(curl --fail --silent --connect-timeout 1 --max-time 2 \
    http://127.0.0.1:8080/health 2>/dev/null || true)"
  if systemctl is-active --quiet "${rogue_service}" \
    && [[ "${response}" == "rescue-debug-listener" ]]; then
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
printf 'Incident 09 is active: another systemd service owns the rescue-web port.\n'
printf 'Open drills/09-port-conflict.md, then enter the host with lab shell.\n'
