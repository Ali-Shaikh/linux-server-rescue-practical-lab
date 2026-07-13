#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="01-service-failure"
readonly state_dir="/var/lib/cloudsprocket-lab"
readonly active_file="${state_dir}/active-drill"
readonly override_dir="/etc/systemd/system/rescue-web.service.d"

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

mkdir -p "${override_dir}"
cat > "${override_dir}/override.conf" <<'EOF'
[Service]
Environment=APP_PORT=not-a-port
EOF

systemctl daemon-reload
systemctl restart rescue-web.service >/dev/null 2>&1 || true
printf '%s\n' "${drill_id}" > "${active_file}"

incident_visible=0
for _ in {1..20}; do
  if ! curl --fail --silent http://127.0.0.1:8080/health >/dev/null 2>&1; then
    incident_visible=1
    break
  fi
  sleep 0.25
done

if (( incident_visible == 0 )); then
  printf 'The incident did not take effect. Run lab reset and try again.\n' >&2
  exit 1
fi

printf 'Incident 01 is active: rescue-web will not stay running.\n'
printf 'Open drills/01-service-failure.md, then enter the host with lab shell.\n'
