#!/usr/bin/env bash
set -Eeuo pipefail

readonly content_dir="/var/lib/rescue-debug"
readonly readiness_script="/usr/local/bin/rescue-debug-listener-ready"
readonly unit_file="/etc/systemd/system/rescue-debug-listener.service"

install -d -o rescue -g rescue -m 0750 "${content_dir}"
cat > "${content_dir}/health" <<'EOF'
rescue-debug-listener
EOF
chown rescue:rescue "${content_dir}/health"
chmod 0640 "${content_dir}/health"

cat > "${readiness_script}" <<'EOF'
#!/usr/bin/env bash
set -u

for _ in {1..50}; do
  response="$(curl --fail --silent --connect-timeout 1 --max-time 2 \
    http://127.0.0.1:8080/health 2>/dev/null || true)"
  if [[ "${response}" == "rescue-debug-listener" ]]; then
    exit 0
  fi
  sleep 0.1
done

printf 'The debug listener did not claim port 8080.\n' >&2
exit 1
EOF

cat > "${unit_file}" <<'EOF'
[Unit]
Description=Temporary rescue debug HTTP listener
After=network.target
Before=rescue-web.service

[Service]
Type=simple
User=rescue
Group=rescue
ExecStart=/usr/bin/python3 -m http.server --bind 0.0.0.0 --directory /var/lib/rescue-debug 8080
ExecStartPost=/usr/local/bin/rescue-debug-listener-ready
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF

chown root:root "${readiness_script}" "${unit_file}"
chmod 0755 "${readiness_script}"
chmod 0644 "${unit_file}"
