#!/usr/bin/env bash
set -Eeuo pipefail

readonly runtime_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -d -m 0755 \
  /etc/rescue-web \
  /etc/systemd/system \
  /opt/rescue-web \
  /usr/local/bin \
  /var/lib/cloudsprocket-lab
install -d -o rescue -g rescue -m 0750 /var/lib/rescue-web

install -o root -g root -m 0755 \
  "${runtime_dir}/rescue-web.py" \
  /opt/rescue-web/server.py
install -o root -g root -m 0755 \
  "${runtime_dir}/rescue-cpu-hog" \
  /usr/local/bin/rescue-cpu-hog
install -o root -g root -m 0755 \
  "${runtime_dir}/rescue-upstream-check" \
  /usr/local/bin/rescue-upstream-check

for unit in \
  rescue-web.service \
  rescue-data-volume.service \
  rescue-cpu-hog.service \
  rescue-upstream-check.service; do
  install -o root -g root -m 0644 \
    "${runtime_dir}/${unit}" \
    "/etc/systemd/system/${unit}"
done

install -o root -g root -m 0644 \
  "${runtime_dir}/rescue-web-config.json" \
  /etc/rescue-web/config.json
install -o root -g root -m 0644 \
  "${runtime_dir}/rescue-web-config.json" \
  /etc/rescue-web/config.json.last-known-good

systemctl enable rescue-web.service >/dev/null

if [[ -d /home/rescue ]] \
  && ! grep -q 'verify is not a command on this server' /home/rescue/.bashrc 2>/dev/null; then
  cat >> /home/rescue/.bashrc <<'EOF'

verify() {
  printf 'verify is not a command on this server.\n'
  printf 'Type exit, then on your laptop run: ./lab verify 01   or   .\\lab.ps1 verify 01\n'
}
EOF
  chown rescue:rescue /home/rescue/.bashrc
fi
