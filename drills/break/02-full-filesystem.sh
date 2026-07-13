#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="02-full-filesystem"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly data_dir="/var/lib/rescue-web"

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

if ! systemctl enable --now rescue-data-volume.service >/dev/null; then
  printf 'The bounded application data volume could not be prepared.\n' >&2
  exit 1
fi

printf '%s\n' "${drill_id}" > "${active_file}"
systemctl restart rescue-web.service >/dev/null 2>&1 || true

incident_visible=0
for _ in {1..20}; do
  if ! curl --fail --silent http://127.0.0.1:8080/health >/dev/null 2>&1; then
    incident_visible=1
    break
  fi
  sleep 0.25
done

if (( incident_visible == 0 )); then
  rm -f "${active_file}"
  systemctl disable --now rescue-data-volume.service >/dev/null 2>&1 || true
  mountpoint --quiet "${data_dir}" && umount "${data_dir}" || true
  systemctl restart rescue-web.service >/dev/null 2>&1 || true
  printf 'The incident did not take effect. Run lab reset and try again.\n' >&2
  exit 1
fi

printf 'Incident 02 is active: rescue-web cannot write to its application filesystem.\n'
printf 'Open drills/02-full-filesystem.md, then enter the host with lab shell.\n'
