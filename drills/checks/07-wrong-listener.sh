#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="07-wrong-listener"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"

container_address() {
  ip -4 -o address show scope global \
    | awk 'NR == 1 {split($4, address, "/"); print address[1]}'
}

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 07 with lab break 07.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

if ! systemctl is-active --quiet rescue-web.service; then
  printf 'NOT FIXED: rescue-web.service is not active. Inspect its status and journal.\n' >&2
  exit 1
fi

network_address="$(container_address)"
if [[ -z "${network_address}" ]]; then
  printf 'NOT FIXED: the container network address could not be determined.\n' >&2
  exit 1
fi

network_ready=0
for _ in {1..20}; do
  if curl --noproxy '*' --fail --silent --connect-timeout 1 \
    "http://${network_address}:8080/health" >/dev/null 2>&1; then
    network_ready=1
    break
  fi
  sleep 0.25
done

if (( network_ready == 0 )); then
  printf 'NOT FIXED: rescue-web still does not answer on its container network interface.\n' >&2
  exit 1
fi

printf 'PASS: rescue-web answers on the network interface used by Docker port forwarding.\n'
