#!/usr/bin/env bash
set -Eeuo pipefail

readonly config_file="/etc/rescue-upstream-port.conf"
readonly known_good="${config_file}.last-known-good"
readonly check_script="/usr/local/bin/rescue-upstream-port-check"
readonly unit_file="/etc/systemd/system/rescue-upstream-port-check.service"

cat > "${check_script}" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

readonly config_file="/etc/rescue-upstream-port.conf"

mapfile -t settings < <(grep -E '^UPSTREAM_URL=' "${config_file}" 2>/dev/null || true)
if (( ${#settings[@]} != 1 )); then
  printf 'Expected exactly one UPSTREAM_URL setting in %s.\n' "${config_file}" >&2
  exit 1
fi

upstream_url="${settings[0]#UPSTREAM_URL=}"
if [[ ! "${upstream_url}" =~ ^http://[a-zA-Z0-9][a-zA-Z0-9.-]*:[0-9]{1,5}/[a-zA-Z0-9._/-]+$ ]]; then
  printf 'UPSTREAM_URL is not a supported internal HTTP URL.\n' >&2
  exit 1
fi

response="$(curl --noproxy '*' --fail --silent --show-error \
  --connect-timeout 1 --max-time 2 "${upstream_url}")"
if [[ "${response}" != *'"service":"upstream-api"'* \
  || "${response}" != *'"status":"ok"'* ]]; then
  printf 'The upstream returned an unexpected health response.\n' >&2
  exit 1
fi

printf 'Upstream health probe passed for %s.\n' "${upstream_url}"
EOF

cat > "${unit_file}" <<'EOF'
[Unit]
Description=Check the external upstream API
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=rescue
Group=rescue
ExecStart=/usr/local/bin/rescue-upstream-port-check
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > "${known_good}" <<'EOF'
UPSTREAM_URL=http://upstream-api:9090/health
EOF

cat > "${config_file}" <<'EOF'
UPSTREAM_URL=http://upstream-api:9191/health
EOF

chown root:root "${check_script}" "${unit_file}" "${known_good}" "${config_file}"
chmod 0755 "${check_script}"
chmod 0644 "${unit_file}" "${known_good}" "${config_file}"
