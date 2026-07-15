#!/usr/bin/env bash
set -Eeuo pipefail

readonly root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly distro="${1:-ubuntu}"
readonly scenario_overlay="scenarios/08-upstream-port/compose.yaml"
readonly upstream_health="scenarios/08-upstream-port/www/health"
readonly upstream_health_backup="scenarios/08-upstream-port/www/health.smoke-backup"
health_file_moved=0
cd "${root_dir}"

fail() {
  printf 'Smoke test failed: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if (( health_file_moved == 1 )) && [[ -f "${upstream_health_backup}" ]]; then
    mv "${upstream_health_backup}" "${upstream_health}"
    health_file_moved=0
  fi
  LAB_DISTRO="${distro}" docker compose --project-name lsr --file compose.yaml \
    --file "${scenario_overlay}" \
    down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -f .local/active-scenario
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

wait_for_upstream() {
  local health
  for _ in {1..30}; do
    health="$(docker container inspect --format \
      '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
      lsr-upstream-api 2>/dev/null || true)"
    [[ "${health}" == "healthy" ]] && return 0
    sleep 1
  done
  fail "the incident 08 upstream companion did not become healthy"
}

wait_for_port_conflict() {
  local listener response rogue_pid
  for _ in {1..30}; do
    response="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      curl --fail --silent http://127.0.0.1:8080/health 2>/dev/null || true)"
    rogue_pid="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      systemctl show --property MainPID --value rescue-debug-listener.service)"
    listener="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      ss -H -ltnp '( sport = :8080 )')"
    if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      systemctl is-active --quiet rescue-debug-listener.service \
      && [[ "${response}" == "rescue-debug-listener" ]] \
      && [[ "${rogue_pid}" =~ ^[1-9][0-9]*$ ]] \
      && [[ "${listener}" == *"pid=${rogue_pid},"* ]]; then
      return 0
    fi
    sleep 1
  done
  fail "incident 09 did not expose the conflicting debug listener"
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

expect_no_active_drill 04
bash ./lab break 04
expect_broken 04

data_owner="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay stat --format='%U:%G' /var/lib/rescue-web)"
data_mode="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay stat --format='%a' /var/lib/rescue-web)"
[[ "${data_owner}" == "root:root" && "${data_mode}" == "750" ]] \
  || fail "incident 04 did not apply the expected least-access ownership fault"

bash ./lab break 04
expect_broken 04

bash ./lab down
bash ./lab up "${distro}"
data_owner="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay stat --format='%U:%G' /var/lib/rescue-web)"
[[ "${data_owner}" == "root:root" ]] \
  || fail "incident 04 was not restored after container recreation"
expect_broken 04

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "chown rescue:rescue /var/lib/rescue-web && chmod 0750 /var/lib/rescue-web && systemctl reset-failed rescue-web.service && systemctl restart rescue-web.service"

bash ./lab verify 04

bash ./lab reset
for drill in 01 02 03 04 05; do
  expect_no_active_drill "${drill}"
done

bash ./lab break 05
expect_broken 05
MSYS_NO_PATHCONV=1 docker exec lsr-relay systemctl is-active --quiet rescue-cpu-hog.service \
  || fail "incident 05 did not start the bounded CPU worker"

bash ./lab break 05
expect_broken 05

bash ./lab down
bash ./lab up "${distro}"
MSYS_NO_PATHCONV=1 docker exec lsr-relay systemctl is-active --quiet rescue-cpu-hog.service \
  || fail "incident 05 was not restored after container recreation"
expect_broken 05

MSYS_NO_PATHCONV=1 docker exec lsr-relay systemctl disable --now rescue-cpu-hog.service
bash ./lab verify 05

bash ./lab reset
for drill in 01 02 03 04 05 06; do
  expect_no_active_drill "${drill}"
done

bash ./lab break 06
expect_broken 06
if MSYS_NO_PATHCONV=1 docker exec lsr-relay python3 -m json.tool \
  /etc/rescue-web/config.json >/dev/null 2>&1; then
  fail "incident 06 did not deploy malformed JSON"
fi

bash ./lab break 06
expect_broken 06

bash ./lab down
bash ./lab up "${distro}"
if MSYS_NO_PATHCONV=1 docker exec lsr-relay python3 -m json.tool \
  /etc/rescue-web/config.json >/dev/null 2>&1; then
  fail "incident 06 was not restored after container recreation"
fi
expect_broken 06

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "install -o root -g root -m 0644 /etc/rescue-web/config.json.last-known-good /etc/rescue-web/config.json && systemctl reset-failed rescue-web.service && systemctl restart rescue-web.service"

bash ./lab verify 06

bash ./lab reset
for drill in 01 02 03 04 05 06 07; do
  expect_no_active_drill "${drill}"
done

bash ./lab break 07
expect_broken 07
network_address="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay ip -4 -o address show scope global \
  | awk 'NR == 1 {split($4, address, "/"); print address[1]}')"
MSYS_NO_PATHCONV=1 docker exec lsr-relay curl --noproxy '*' --fail --silent \
  http://127.0.0.1:8080/health >/dev/null \
  || fail "incident 07 did not retain its loopback health path"
if MSYS_NO_PATHCONV=1 docker exec lsr-relay curl --noproxy '*' --fail --silent \
  --connect-timeout 1 "http://${network_address}:8080/health" >/dev/null 2>&1; then
  fail "incident 07 unexpectedly answered on the container network interface"
fi

bash ./lab break 07
expect_broken 07

bash ./lab down
bash ./lab up "${distro}"
expect_broken 07
network_address="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay ip -4 -o address show scope global \
  | awk 'NR == 1 {split($4, address, "/"); print address[1]}')"
MSYS_NO_PATHCONV=1 docker exec lsr-relay curl --noproxy '*' --fail --silent \
  http://127.0.0.1:8080/health >/dev/null \
  || fail "incident 07 lost its loopback health path after container recreation"
if MSYS_NO_PATHCONV=1 docker exec lsr-relay curl --noproxy '*' --fail --silent \
  --connect-timeout 1 "http://${network_address}:8080/health" >/dev/null 2>&1; then
  fail "incident 07 did not restore its loopback-only listener after container recreation"
fi

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "install -o root -g root -m 0644 /etc/rescue-web/config.json.last-known-good /etc/rescue-web/config.json && systemctl restart rescue-web.service"

bash ./lab verify 07

bash ./lab reset
for drill in 01 02 03 04 05 06 07 08; do
  expect_no_active_drill "${drill}"
done

# A failed break after the companion starts must roll back both the service and
# its ignored overlay marker without disturbing the healthy learner node.
mv "${upstream_health}" "${upstream_health_backup}"
health_file_moved=1
set +e
bash ./lab break 08
failed_break_code=$?
set -e
mv "${upstream_health_backup}" "${upstream_health}"
health_file_moved=0
[[ ${failed_break_code} -ne 0 ]] \
  || fail "incident 08 unexpectedly succeeded without its health response"
[[ ! -f .local/active-scenario ]] \
  || fail "failed incident 08 left an active scenario marker"
if docker container inspect lsr-upstream-api >/dev/null 2>&1; then
  fail "failed incident 08 left its upstream companion behind"
fi
expect_no_active_drill 08
MSYS_NO_PATHCONV=1 docker exec lsr-relay systemctl is-active --quiet rescue-web.service \
  || fail "failed incident 08 disturbed the learner service"

bash ./lab break 08
wait_for_upstream
expect_broken 08
MSYS_NO_PATHCONV=1 docker exec lsr-relay systemctl is-failed --quiet \
  rescue-upstream-port-check.service \
  || fail "incident 08 did not fail the upstream systemd probe"
[[ "$(tr -d '\r\n' < .local/active-scenario)" == "${scenario_overlay}" ]] \
  || fail "incident 08 did not save its scenario overlay"

# Applying an already-active scenario incident must preserve the broken state.
bash ./lab break 08
expect_broken 08

bash ./lab down
if docker container inspect lsr-upstream-api >/dev/null 2>&1; then
  fail "lab down did not stop and remove the upstream companion"
fi
bash ./lab up "${distro}"
wait_for_upstream
expect_broken 08
MSYS_NO_PATHCONV=1 docker exec lsr-relay systemctl is-failed --quiet \
  rescue-upstream-port-check.service \
  || fail "incident 08 was not restored after container recreation"

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "install -o root -g root -m 0644 /etc/rescue-upstream-port.conf.last-known-good /etc/rescue-upstream-port.conf && systemctl reset-failed rescue-upstream-port-check.service && systemctl restart rescue-upstream-port-check.service"

bash ./lab verify 08

bash ./lab reset
[[ ! -f .local/active-scenario ]] \
  || fail "lab reset left the incident 08 scenario marker behind"
if docker container inspect lsr-upstream-api >/dev/null 2>&1; then
  fail "lab reset left the incident 08 upstream companion behind"
fi
for drill in 01 02 03 04 05 06 07 08; do
  expect_no_active_drill "${drill}"
done

expect_no_active_drill 09
bash ./lab break 09
wait_for_port_conflict
expect_broken 09
MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  systemctl is-enabled --quiet rescue-debug-listener.service \
  || fail "incident 09 did not enable the conflicting listener for the next boot"

# Applying an already-active portable incident must preserve the broken state.
bash ./lab break 09
wait_for_port_conflict
expect_broken 09

bash ./lab down
bash ./lab up "${distro}"
wait_for_port_conflict
expect_broken 09

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "systemctl disable --now rescue-debug-listener.service && systemctl reset-failed rescue-web.service && systemctl restart rescue-web.service"
bash ./lab verify 09

bash ./lab reset
if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  systemctl cat rescue-debug-listener.service >/dev/null 2>&1; then
  fail "lab reset left the incident 09 debug-listener unit behind"
fi
for drill in 01 02 03 04 05 06 07 08 09; do
  expect_no_active_drill "${drill}"
done

printf 'Smoke test passed for %s.\n' "${distro}"
