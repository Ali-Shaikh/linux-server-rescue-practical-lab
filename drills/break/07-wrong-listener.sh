#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="07-wrong-listener"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly config_file="/etc/rescue-web/config.json"
readonly known_good="/etc/rescue-web/config.json.last-known-good"

container_address() {
  ip -4 -o address show scope global \
    | awk 'NR == 1 {split($4, address, "/"); print address[1]}'
}

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

network_address="$(container_address)"
if [[ -z "${network_address}" ]]; then
  printf 'The container network address could not be determined.\n' >&2
  exit 1
fi

bash /opt/lab/drills/fixtures/07-wrong-listener.sh
systemctl restart rescue-web.service >/dev/null 2>&1 || true

incident_visible=0
for _ in {1..20}; do
  if curl --noproxy '*' --fail --silent http://127.0.0.1:8080/health >/dev/null 2>&1 \
    && ! curl --noproxy '*' --fail --silent --connect-timeout 1 \
      "http://${network_address}:8080/health" >/dev/null 2>&1; then
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
printf 'Incident 07 is active: rescue-web answers only on the container loopback interface.\n'
printf 'Open drills/07-wrong-listener.md, then enter the host with lab shell.\n'
