#!/usr/bin/env bash
set -Eeuo pipefail

readonly state_dir="/var/lib/rescue-backup"
readonly backup_script="/usr/local/bin/rescue-backup-run"
readonly volume_script="/usr/local/bin/rescue-backup-volume"
readonly volume_file="/etc/systemd/system/rescue-backup-volume.service"
readonly service_file="/etc/systemd/system/rescue-backup.service"
readonly timer_file="/etc/systemd/system/rescue-backup.timer"

install -d -o rescue -g rescue -m 0750 "${state_dir}"

cat > "${backup_script}" <<'PYTHON'
#!/usr/bin/env python3
"""Create one real rescue-web tar archive without applying retention."""

import tarfile
import time
from pathlib import Path


backup_dir = Path("/var/lib/rescue-web/backups")
sequence_file = Path("/var/lib/rescue-backup/next-sequence")
config_file = Path("/etc/rescue-web/config.json")
sequence = int(sequence_file.read_text(encoding="utf-8").strip())
complete = backup_dir / f"backup-{sequence:04d}.tar"
partial = backup_dir / f".backup-{sequence:04d}.tar.partial"
partial.unlink(missing_ok=True)

with tarfile.open(partial, mode="w") as archive:
    archive.add(config_file, arcname="etc/rescue-web/config.json", recursive=False)
    padding = tarfile.TarInfo("var/lib/rescue-web/cache.snapshot")
    padding.size = 6 * 1024 * 1024
    padding.mtime = int(time.time())
    padding.mode = 0o600
    padding.uname = "rescue"
    padding.gname = "rescue"
    with Path("/dev/zero").open("rb", buffering=0) as zeros:
        archive.addfile(padding, zeros)

partial.replace(complete)
sequence_file.write_text(f"{sequence + 1}\n", encoding="utf-8")
print(f"Created {complete}", flush=True)
PYTHON

cat > "${volume_script}" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

readonly data_dir="/var/lib/rescue-web"
readonly backup_dir="${data_dir}/backups"
readonly sequence_file="/var/lib/rescue-backup/next-sequence"
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
    -o "size=24m,nr_inodes=2048,mode=0750,uid=${rescue_uid},gid=${rescue_gid},nosuid,nodev,noexec" \
    rescue-backup-volume "${data_dir}"
fi

rm -rf "${backup_dir}"
rm -f "${data_dir}/last-startup"
install -d -o rescue -g rescue -m 0750 "${backup_dir}"
printf '1\n' > "${sequence_file}"
chown rescue:rescue "${sequence_file}"
chmod 0640 "${sequence_file}"

exhausted=0
for _ in {1..8}; do
  if ! runuser --user rescue -- /usr/local/bin/rescue-backup-run >/dev/null; then
    exhausted=1
    break
  fi
done

complete_count="$(find "${backup_dir}" -xdev -maxdepth 1 -type f \
  -name 'backup-*.tar' | wc -l)"
partial_file="$(find "${backup_dir}" -xdev -maxdepth 1 -type f \
  -name '.backup-*.tar.partial' -print -quit)"
used_percent="$(df -P "${data_dir}" | awk 'NR == 2 {print $5}')"
if (( exhausted == 0 )) || (( complete_count < 2 )) \
  || [[ -z "${partial_file}" || "${used_percent}" != "100%" ]]; then
  printf 'Backup preparation did not produce the expected full filesystem.\n' >&2
  exit 1
fi
EOF

cat > "${volume_file}" <<'EOF'
[Unit]
Description=Prepare the bounded rescue-web backup filesystem
Before=rescue-backup.service rescue-web.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rescue-backup-volume
RemainAfterExit=yes
TimeoutStartSec=30s

[Install]
WantedBy=multi-user.target
EOF

cat > "${service_file}" <<'EOF'
[Unit]
Description=Create a local rescue-web backup without retention
Requires=rescue-backup-volume.service
After=rescue-backup-volume.service

[Service]
Type=oneshot
User=rescue
Group=rescue
ExecStart=/usr/local/bin/rescue-backup-run
TimeoutStartSec=15s
EOF

cat > "${timer_file}" <<'EOF'
[Unit]
Description=Run local rescue-web backups repeatedly
Requires=rescue-backup-volume.service
After=rescue-backup-volume.service

[Timer]
OnActiveSec=2s
OnUnitInactiveSec=2s
AccuracySec=100ms
Unit=rescue-backup.service

[Install]
WantedBy=timers.target
EOF

chown root:root \
  "${backup_script}" "${volume_script}" \
  "${volume_file}" "${service_file}" "${timer_file}"
chmod 0755 "${backup_script}" "${volume_script}"
chmod 0644 "${volume_file}" "${service_file}" "${timer_file}"
