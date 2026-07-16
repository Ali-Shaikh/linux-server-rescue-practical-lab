#!/usr/bin/env bash
set -Eeuo pipefail

readonly state_dir="/var/lib/rescue-deleted-log"
readonly volume_script="/usr/local/bin/rescue-deleted-log-volume"
readonly holder_script="/usr/local/bin/rescue-deleted-log-holder"
readonly volume_file="/etc/systemd/system/rescue-deleted-log-volume.service"
readonly holder_file="/etc/systemd/system/rescue-deleted-log-holder.service"

install -d -o root -g root -m 0750 "${state_dir}"

cat > "${volume_script}" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

readonly data_dir="/var/lib/rescue-web"
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
    -o "size=16m,nr_inodes=1024,mode=0750,uid=${rescue_uid},gid=${rescue_gid},nosuid,nodev,noexec" \
    rescue-deleted-log "${data_dir}"
fi

rm -f "${data_dir}/last-startup"
EOF

cat > "${holder_script}" <<'EOF'
#!/usr/bin/env python3
"""Fill a bounded filesystem, unlink the log, and retain its descriptor."""

import errno
import os
import signal
from pathlib import Path


log_path = Path("/var/lib/rescue-web/archived-access.log")
ready_path = Path("/run/rescue-deleted-log/ready")
ready_path.unlink(missing_ok=True)

with log_path.open("wb", buffering=0) as log_file:
    log_path.unlink()
    chunk = b"\0" * (1024 * 1024)
    while True:
        try:
            log_file.write(chunk)
        except OSError as error:
            if error.errno != errno.ENOSPC:
                raise
            break

    ready_path.write_text(f"pid={os.getpid()}\n", encoding="utf-8")
    while True:
        signal.pause()
EOF

cat > "${volume_file}" <<'EOF'
[Unit]
Description=Prepare the bounded rescue-web log filesystem
Before=rescue-deleted-log-holder.service rescue-web.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rescue-deleted-log-volume
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > "${holder_file}" <<'EOF'
[Unit]
Description=Legacy rescue-web log retention worker
Requires=rescue-deleted-log-volume.service
After=rescue-deleted-log-volume.service
Before=rescue-web.service

[Service]
Type=simple
User=rescue
Group=rescue
RuntimeDirectory=rescue-deleted-log
RuntimeDirectoryMode=0750
ExecStart=/usr/local/bin/rescue-deleted-log-holder
ExecStartPost=/bin/bash -c 'for _ in {1..100}; do [[ -f /run/rescue-deleted-log/ready ]] && exit 0; sleep 0.05; done; exit 1'
TimeoutStartSec=15s
TimeoutStopSec=5s

[Install]
WantedBy=multi-user.target
EOF

chown root:root \
  "${volume_script}" "${holder_script}" "${volume_file}" "${holder_file}"
chmod 0755 "${volume_script}" "${holder_script}"
chmod 0644 "${volume_file}" "${holder_file}"
