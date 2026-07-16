#!/usr/bin/env bash
set -Eeuo pipefail

readonly state_dir="/var/lib/rescue-regression"
readonly bad_config="${state_dir}/bad-config.json"
readonly deploy_script="/usr/local/bin/rescue-config-regression"
readonly service_file="/etc/systemd/system/rescue-config-regression.service"
readonly timer_file="/etc/systemd/system/rescue-config-regression.timer"

install -d -o root -g root -m 0750 "${state_dir}"
cat > "${bad_config}" <<'EOF'
{
  "service_name": "rescue-web",
  "listen_port": 8081,
  "bind_host": "0.0.0.0"
}
EOF

cat > "${deploy_script}" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

install -o root -g root -m 0644 \
  /var/lib/rescue-regression/bad-config.json \
  /etc/rescue-web/config.json
printf 'Scheduled deployment restored rescue-web port 8081.\n'
systemctl reset-failed rescue-web.service >/dev/null 2>&1 || true
systemctl restart rescue-web.service >/dev/null 2>&1 || true
EOF

cat > "${service_file}" <<'EOF'
[Unit]
Description=Reapply the staged rescue-web configuration
After=rescue-web.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rescue-config-regression
TimeoutStartSec=10s
EOF

cat > "${timer_file}" <<'EOF'
[Unit]
Description=Reapply the staged rescue-web configuration repeatedly

[Timer]
OnActiveSec=3s
OnUnitActiveSec=3s
AccuracySec=100ms
Unit=rescue-config-regression.service

[Install]
WantedBy=timers.target
EOF

chown root:root "${bad_config}" "${deploy_script}" "${service_file}" "${timer_file}"
chmod 0644 "${bad_config}" "${service_file}" "${timer_file}"
chmod 0755 "${deploy_script}"
