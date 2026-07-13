#!/usr/bin/env bash
set -Eeuo pipefail

readonly root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly distro="${1:-ubuntu}"
cd "${root_dir}"

fail() {
  printf 'Smoke test failed: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  LAB_DISTRO="${distro}" docker compose --project-name lsr --file compose.yaml \
    down --volumes --remove-orphans >/dev/null 2>&1 || true
}

expect_no_active_drill() {
  local drill="$1" verify_code
  set +e
  bash ./lab verify "${drill}"
  verify_code=$?
  set -e
  [[ ${verify_code} -eq 2 ]] \
    || fail "verify ${drill} on a healthy lab returned ${verify_code}, expected 2"
}

expect_broken() {
  local drill="$1"
  if bash ./lab verify "${drill}"; then
    fail "incident ${drill} unexpectedly passed verification"
  fi
}

cleanup
trap cleanup EXIT

bash ./lab doctor "${distro}"
bash ./lab up "${distro}"

actual_distro="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay sh -c '. /etc/os-release; printf %s "$ID"')"
[[ "${actual_distro}" == "${distro}" ]] \
  || fail "expected ${distro}, container reports ${actual_distro}"

expect_no_active_drill 01
bash ./lab break 01
expect_broken 01
# Applying an already-active incident must preserve the broken state.
bash ./lab break 01
expect_broken 01

bash ./lab down
bash ./lab up "${distro}"
MSYS_NO_PATHCONV=1 docker exec lsr-relay grep --quiet \
  'Environment=APP_PORT=not-a-port' /etc/systemd/system/rescue-web.service.d/override.conf \
  || fail "incident 01 was not restored after container recreation"
expect_broken 01

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "printf '[Service]\\nEnvironment=APP_PORT=8080\\n' > /etc/systemd/system/rescue-web.service.d/override.conf && systemctl daemon-reload && systemctl reset-failed rescue-web.service && systemctl restart rescue-web.service"

bash ./lab verify 01

bash ./lab reset
expect_no_active_drill 01
expect_no_active_drill 02

bash ./lab break 02
expect_broken 02
# Applying an already-active incident must preserve the broken state.
bash ./lab break 02
expect_broken 02

filesystem_type="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay findmnt --noheadings --output FSTYPE --target /var/lib/rescue-web | tr -d '[:space:]')"
used_percent="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay df -P /var/lib/rescue-web | awk 'NR == 2 {print $5}')"
[[ "${filesystem_type}" == "tmpfs" && "${used_percent}" == "100%" ]] \
  || fail "incident 02 did not create the expected full bounded tmpfs"

bash ./lab down
bash ./lab up "${distro}"
filesystem_type="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay findmnt --noheadings --output FSTYPE --target /var/lib/rescue-web | tr -d '[:space:]')"
used_percent="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay df -P /var/lib/rescue-web | awk 'NR == 2 {print $5}')"
[[ "${filesystem_type}" == "tmpfs" && "${used_percent}" == "100%" ]] \
  || fail "incident 02 was not restored after container recreation"
expect_broken 02

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "rm -f /var/lib/rescue-web/old-debug.log && systemctl reset-failed rescue-web.service && systemctl restart rescue-web.service"

bash ./lab verify 02

bash ./lab reset
expect_no_active_drill 01
expect_no_active_drill 02
expect_no_active_drill 03

bash ./lab break 03
expect_broken 03

host_answer="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay getent ahostsv4 rescue-api.internal | awk 'NR == 1 {print $1}')"
dns_answer="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay dig +short @127.0.0.11 rescue-api.internal A | awk 'NR == 1 {print $1}')"
[[ "${host_answer}" == "203.0.113.99" && -n "${dns_answer}" && "${dns_answer}" != "${host_answer}" ]] \
  || fail "incident 03 did not shadow the embedded DNS answer through the host resolver"

# Applying an already-active incident must preserve the broken state.
bash ./lab break 03
expect_broken 03

bash ./lab down
bash ./lab up "${distro}"
host_answer="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay getent ahostsv4 rescue-api.internal | awk 'NR == 1 {print $1}')"
[[ "${host_answer}" == "203.0.113.99" ]] \
  || fail "incident 03 was not restored after container recreation"
expect_broken 03

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "grep -v 'cloudsprocket-dns-ghost' /etc/hosts > /run/hosts.clean && cat /run/hosts.clean > /etc/hosts && rm /run/hosts.clean && systemctl reset-failed rescue-upstream-check.service && systemctl restart rescue-upstream-check.service"

bash ./lab verify 03

bash ./lab reset
expect_no_active_drill 01
expect_no_active_drill 02
expect_no_active_drill 03

printf 'Smoke test passed for %s.\n' "${distro}"
