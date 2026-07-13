#!/usr/bin/env bash
set -Eeuo pipefail

cat > /etc/rescue-web/config.json <<'EOF'
{
  "service_name": "rescue-web",
  "listen_port": 8080,
  "bind_host": "127.0.0.1"
}
EOF
chown root:root /etc/rescue-web/config.json
chmod 0644 /etc/rescue-web/config.json
