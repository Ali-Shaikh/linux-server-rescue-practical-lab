#!/usr/bin/env bash
set -Eeuo pipefail

readonly volume_script="/usr/local/bin/rescue-inode-volume"
readonly volume_file="/etc/systemd/system/rescue-inode-volume.service"

cat > "${volume_script}" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

readonly data_dir="/var/lib/rescue-web"
readonly sessions_dir="${data_dir}/sessions"
rescue_uid="$(id -u rescue)"
rescue_gid="$(id -g rescue)"

install -d -o rescue -g rescue -m 0750 "${data_dir}"
if mountpoint --quiet "${data_dir}"; then
  filesystem_type="$(findmnt --noheadings --output FSTYPE --target "${data_dir}" | tr -d '[:space:]')"
  if [[ "${filesystem_type}" != "tmpfs" ]]; then
    printf '%s is already a %s mount, not the expected tmpfs.\n' \
      "${data_dir}" "${filesystem_type}" >&2
    exit 1
  fi
else
  mount -t tmpfs \
    -o "size=16m,nr_inodes=64,mode=0750,uid=${rescue_uid},gid=${rescue_gid},nosuid,nodev,noexec" \
    rescue-inode-volume "${data_dir}"
fi

rm -rf "${sessions_dir}"
rm -f "${data_dir}/last-startup"
install -d -o rescue -g rescue -m 0750 "${sessions_dir}"

exhausted=0
for sequence in {1..128}; do
  session_file="$(printf '%s/stale-%04d.session' "${sessions_dir}" "${sequence}")"
  if ! runuser --user rescue -- touch "${session_file}" 2>/dev/null; then
    exhausted=1
    break
  fi
done

if (( exhausted == 0 )); then
  printf 'The bounded filesystem did not exhaust its inode allowance.\n' >&2
  exit 1
fi

inode_percent="$(df -Pi "${data_dir}" | awk 'NR == 2 {print $5}')"
if [[ "${inode_percent}" != "100%" ]]; then
  printf 'Expected 100%% inode use, observed %s.\n' "${inode_percent}" >&2
  exit 1
fi
EOF

cat > "${volume_file}" <<'EOF'
[Unit]
Description=Prepare the bounded rescue-web inode filesystem
Before=rescue-web.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rescue-inode-volume
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chown root:root "${volume_script}" "${volume_file}"
chmod 0755 "${volume_script}"
chmod 0644 "${volume_file}"
