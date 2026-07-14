#!/usr/bin/env bash
set -Eeuo pipefail

readonly override_dir="/etc/systemd/system/rescue-web.service.d"

mkdir -p "${override_dir}"
cat > "${override_dir}/override.conf" <<'EOF'
[Service]
Environment=APP_PORT=not-a-port
EOF
