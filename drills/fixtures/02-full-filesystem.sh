#!/usr/bin/env bash
set -Eeuo pipefail

readonly data_dir="/var/lib/rescue-web"
readonly filler="${data_dir}/old-debug.log"

rescue_uid="$(id -u rescue)"
rescue_gid="$(id -g rescue)"
mkdir -p "${data_dir}"

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
    rescue-data "${data_dir}"
fi

rm -f "${filler}" "${data_dir}/last-startup"
if dd if=/dev/zero of="${filler}" bs=1M count=32 status=none 2>/dev/null; then
  printf 'The bounded data volume unexpectedly accepted more than 16 MiB.\n' >&2
  rm -f "${filler}"
  exit 1
fi

used_percent="$(df -P "${data_dir}" | awk 'NR == 2 {print $5}')"
if [[ "${used_percent}" != "100%" ]]; then
  printf 'The data volume reached %s rather than the expected 100%%.\n' \
    "${used_percent:-an unknown utilisation}" >&2
  exit 1
fi
