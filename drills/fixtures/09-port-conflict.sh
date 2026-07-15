#!/usr/bin/env bash
set -Eeuo pipefail

readonly content_dir="/var/lib/rescue-debug"
readonly unit_file="/etc/systemd/system/rescue-debug-listener.service"

install -d -o rescue -g rescue -m 0750 "${content_dir}"
cat > "${content_dir}/health" <<'EOF'
rescue-debug-listener
EOF
chown rescue:rescue "${content_dir}/health"
chmod 0640 "${content_dir}/health"

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
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF

chown root:root "${unit_file}"
chmod 0644 "${unit_file}"
