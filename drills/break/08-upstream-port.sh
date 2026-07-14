#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="08-upstream-port"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly service="rescue-upstream-port-check.service"
readonly correct_url="http://upstream-api:9090/health"
readonly wrong_url="http://upstream-api:9191/health"

clean_fault() {
  systemctl disable --now "${service}" >/dev/null 2>&1 || true
  systemctl reset-failed "${service}" >/dev/null 2>&1 || true
  rm -f \
    /etc/rescue-upstream-port.conf \
    /etc/rescue-upstream-port.conf.last-known-good \
    /etc/systemd/system/rescue-upstream-port-check.service \
    /usr/local/bin/rescue-upstream-port-check
  systemctl daemon-reload >/dev/null 2>&1 || true
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

upstream_ready=0
for _ in {1..20}; do
  if NO_PROXY='*' no_proxy='*' \
    curl --fail --silent --connect-timeout 1 --max-time 2 "${correct_url}" \
    | grep --quiet '"service":"upstream-api"'; then
    upstream_ready=1
    break
  fi
  sleep 0.25
done

if (( upstream_ready == 0 )); then
  printf 'The upstream companion is not ready at its known-good endpoint.\n' >&2
  exit 1
fi

bash /opt/lab/drills/fixtures/08-upstream-port.sh
systemctl daemon-reload
systemctl enable "${service}" >/dev/null
systemctl restart "${service}" >/dev/null 2>&1 || true

if ! systemctl is-failed --quiet "${service}" \
  || NO_PROXY='*' no_proxy='*' \
    curl --fail --silent --connect-timeout 1 --max-time 2 "${wrong_url}" \
      >/dev/null 2>&1; then
  clean_fault
  printf 'The incident did not take effect. Run lab reset and try again.\n' >&2
  exit 1
fi

printf '%s\n' "${drill_id}" > "${active_file}"
printf 'Incident 08 is active: the external upstream health probe is failing.\n'
printf 'Open drills/08-upstream-port.md, then enter the host with lab shell.\n'
