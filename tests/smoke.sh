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

wait_for_scheduled_regression() {
  local response
  for _ in {1..30}; do
    response="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      curl --fail --silent http://127.0.0.1:8081/health 2>/dev/null || true)"
    if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      systemctl is-active --quiet rescue-config-regression.timer \
      && MSYS_NO_PATHCONV=1 docker exec lsr-relay \
        systemctl is-enabled --quiet rescue-config-regression.timer \
      && [[ "${response}" == *'"service": "rescue-web"'* ]] \
      && ! MSYS_NO_PATHCONV=1 docker exec lsr-relay \
        curl --fail --silent http://127.0.0.1:8080/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  fail "incident 10 did not expose the recurring port regression"
}

wait_for_rescue_web() {
  local port="$1" response
  for _ in {1..30}; do
    response="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      curl --fail --silent "http://127.0.0.1:${port}/health" 2>/dev/null || true)"
    if [[ "${response}" == *'"service": "rescue-web"'* ]]; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

wait_for_deleted_open_file() {
  local deleted_fd holder_pid used_percent
  for _ in {1..40}; do
    holder_pid="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      systemctl show --property MainPID --value rescue-deleted-log-holder.service)"
    deleted_fd=""
    if [[ "${holder_pid}" =~ ^[1-9][0-9]*$ ]]; then
      deleted_fd="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
        find "/proc/${holder_pid}/fd" -maxdepth 1 \
          -lname '/var/lib/rescue-web/archived-access.log (deleted)' \
          -print -quit 2>/dev/null || true)"
    fi
    used_percent="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      df -P /var/lib/rescue-web | awk 'NR == 2 {print $5}')"
    if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      systemctl is-active --quiet rescue-deleted-log-holder.service \
      && MSYS_NO_PATHCONV=1 docker exec lsr-relay \
        systemctl is-enabled --quiet rescue-deleted-log-holder.service \
      && [[ -n "${deleted_fd}" && "${used_percent}" == "100%" ]] \
      && ! MSYS_NO_PATHCONV=1 docker exec lsr-relay \
        curl --fail --silent http://127.0.0.1:8080/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  fail "incident 11 did not expose the deleted open log"
}

wait_for_inode_exhaustion() {
  local block_percent inode_percent
  for _ in {1..40}; do
    inode_percent="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      df -Pi /var/lib/rescue-web | awk 'NR == 2 {print $5}')"
    block_percent="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      df -P /var/lib/rescue-web | awk 'NR == 2 {print $5}')"
    if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      systemctl is-active --quiet rescue-inode-volume.service \
      && MSYS_NO_PATHCONV=1 docker exec lsr-relay \
        systemctl is-enabled --quiet rescue-inode-volume.service \
      && [[ "${inode_percent}" == "100%" ]] \
      && [[ "${block_percent}" != "100%" ]] \
      && MSYS_NO_PATHCONV=1 docker exec lsr-relay \
        find /var/lib/rescue-web/sessions -xdev -type f \
          -name 'stale-*.session' -print -quit | grep --quiet . \
      && ! MSYS_NO_PATHCONV=1 docker exec lsr-relay \
        curl --fail --silent http://127.0.0.1:8080/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  fail "incident 12 did not expose inode exhaustion with free blocks"
}

backup_storage_is_full() {
  local complete_count partial_file used_percent
  used_percent="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
    df -P /var/lib/rescue-web | awk 'NR == 2 {print $5}')"
  complete_count="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
    find /var/lib/rescue-web/backups -xdev -maxdepth 1 -type f \
      -name 'backup-*.tar' | wc -l)"
  partial_file="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay \
    find /var/lib/rescue-web/backups -xdev -maxdepth 1 -type f \
      -name '.backup-*.tar.partial' -print -quit)"
  MSYS_NO_PATHCONV=1 docker exec lsr-relay \
    systemctl is-active --quiet rescue-backup.timer \
    && MSYS_NO_PATHCONV=1 docker exec lsr-relay \
      systemctl is-enabled --quiet rescue-backup.timer \
    && [[ "${used_percent}" == "100%" ]] \
    && (( complete_count >= 2 )) \
    && [[ -n "${partial_file}" ]]
}

wait_for_backup_storage_full() {
  for _ in {1..40}; do
    if backup_storage_is_full; then
      return 0
    fi
    sleep 0.25
  done
  fail "incident 13 recurring backups did not refill the filesystem"
}

wait_for_backup_sprawl() {
  for _ in {1..40}; do
    if backup_storage_is_full \
      && ! MSYS_NO_PATHCONV=1 docker exec lsr-relay \
        curl --fail --silent http://127.0.0.1:8080/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  fail "incident 13 did not expose recurring backup filesystem growth"
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

# Occupying the bad port forces a failed break after the timer job starts. The
# rollback must remove every scheduled-regression artefact and restore the web
# service without recording an active incident.
MSYS_NO_PATHCONV=1 docker exec lsr-relay systemd-run --quiet --collect \
  --unit=rescue-break-blocker.service \
  /usr/bin/python3 -m http.server 8081 --bind 127.0.0.1
blocker_ready=0
for _ in {1..20}; do
  if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
    curl --fail --silent http://127.0.0.1:8081/ >/dev/null 2>&1; then
    blocker_ready=1
    break
  fi
  sleep 0.25
done
(( blocker_ready == 1 )) \
  || fail "the incident 10 failed-break blocker did not start"

set +e
bash ./lab break 10
failed_break_code=$?
set -e
[[ ${failed_break_code} -ne 0 ]] \
  || fail "incident 10 unexpectedly succeeded while port 8081 was occupied"
MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "journalctl -u rescue-config-regression.service --no-pager | grep --quiet 'Scheduled deployment restored'" \
  || fail "incident 10 failed before its recurring job started"
expect_no_active_drill 10
if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  systemctl cat rescue-config-regression.timer >/dev/null 2>&1; then
  fail "a failed incident 10 break left the regression timer behind"
fi
if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  test -e /usr/local/bin/rescue-config-regression; then
  fail "a failed incident 10 break left its deployment script behind"
fi
MSYS_NO_PATHCONV=1 docker exec lsr-relay curl --fail --silent \
  http://127.0.0.1:8080/health | grep --quiet '"service": "rescue-web"' \
  || fail "a failed incident 10 break did not restore rescue-web"
MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  systemctl stop rescue-break-blocker.service

expect_no_active_drill 10
bash ./lab break 10
wait_for_scheduled_regression
expect_broken 10

# Pause only the timer clock so a slow runner cannot hide the temporary repair.
# It remains enabled and is restarted immediately afterwards to reapply the fault.
MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "systemctl stop rescue-config-regression.timer && install -o root -g root -m 0644 /etc/rescue-web/config.json.last-known-good /etc/rescue-web/config.json && systemctl restart rescue-web.service"
wait_for_rescue_web 8080 \
  || fail "incident 10 did not allow the expected temporary file-only repair"
MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  systemctl start rescue-config-regression.timer
wait_for_scheduled_regression
expect_broken 10

# Applying an already-active portable incident must preserve the recurring fault.
bash ./lab break 10
wait_for_scheduled_regression
expect_broken 10

bash ./lab down
bash ./lab up "${distro}"
wait_for_scheduled_regression
expect_broken 10

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "systemctl disable --now rescue-config-regression.timer && systemctl stop rescue-config-regression.service && install -o root -g root -m 0644 /etc/rescue-web/config.json.last-known-good /etc/rescue-web/config.json && systemctl reset-failed rescue-web.service && systemctl restart rescue-web.service"
bash ./lab verify 10

bash ./lab reset
if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  systemctl cat rescue-config-regression.timer >/dev/null 2>&1; then
  fail "lab reset left the incident 10 regression timer behind"
fi
if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  systemctl cat rescue-config-regression.service >/dev/null 2>&1; then
  fail "lab reset left the incident 10 regression service behind"
fi
for drill in 01 02 03 04 05 06 07 08 09 10; do
  expect_no_active_drill "${drill}"
done

expect_no_active_drill 11
bash ./lab break 11
wait_for_deleted_open_file
expect_broken 11

# Removing visible files cannot release blocks retained by an open descriptor.
MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "rm -f /var/lib/rescue-web/* && systemctl reset-failed rescue-web.service && systemctl restart rescue-web.service >/dev/null 2>&1 || true"
wait_for_deleted_open_file
expect_broken 11

# Applying an already-active portable incident must preserve the hidden usage.
bash ./lab break 11
wait_for_deleted_open_file
expect_broken 11

bash ./lab down
bash ./lab up "${distro}"
wait_for_deleted_open_file
expect_broken 11

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "systemctl disable --now rescue-deleted-log-holder.service && systemctl reset-failed rescue-web.service && systemctl restart rescue-web.service"
bash ./lab verify 11

bash ./lab reset
if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  systemctl cat rescue-deleted-log-holder.service >/dev/null 2>&1; then
  fail "lab reset left the incident 11 deleted-log holder unit behind"
fi
if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  systemctl cat rescue-deleted-log-volume.service >/dev/null 2>&1; then
  fail "lab reset left the incident 11 data-volume unit behind"
fi
for drill in 01 02 03 04 05 06 07 08 09 10 11; do
  expect_no_active_drill "${drill}"
done

expect_no_active_drill 12
bash ./lab break 12
wait_for_inode_exhaustion
expect_broken 12

# Applying an already-active portable incident must preserve inode exhaustion.
bash ./lab break 12
wait_for_inode_exhaustion
expect_broken 12

bash ./lab down
bash ./lab up "${distro}"
wait_for_inode_exhaustion
expect_broken 12

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "find /var/lib/rescue-web/sessions -xdev -type f -name 'stale-*.session' -delete && systemctl reset-failed rescue-web.service && systemctl restart rescue-web.service"
bash ./lab verify 12

bash ./lab reset
if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  systemctl cat rescue-inode-volume.service >/dev/null 2>&1; then
  fail "lab reset left the incident 12 inode-volume unit behind"
fi
for drill in 01 02 03 04 05 06 07 08 09 10 11 12; do
  expect_no_active_drill "${drill}"
done

expect_no_active_drill 13
bash ./lab break 13
wait_for_backup_sprawl
expect_broken 13

# Pause only the timer clock to make the temporary cleanup deterministic. The
# timer remains enabled and is restarted immediately after rescue-web recovers.
MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "systemctl stop rescue-backup.timer && find /var/lib/rescue-web/backups -xdev -maxdepth 1 -type f -name '.backup-*.tar.partial' -delete && systemctl reset-failed rescue-web.service && systemctl restart rescue-web.service"
wait_for_rescue_web 8080 \
  || fail "incident 13 did not allow the expected temporary space-only repair"
MSYS_NO_PATHCONV=1 docker exec lsr-relay systemctl start rescue-backup.timer
wait_for_backup_storage_full
MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "systemctl reset-failed rescue-web.service && systemctl restart rescue-web.service >/dev/null 2>&1 || true"
wait_for_backup_sprawl
expect_broken 13

# Applying an already-active portable incident must preserve backup growth.
bash ./lab break 13
wait_for_backup_sprawl
expect_broken 13

bash ./lab down
bash ./lab up "${distro}"
wait_for_backup_sprawl
expect_broken 13

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "systemctl disable --now rescue-backup.timer && systemctl stop rescue-backup.service && find /var/lib/rescue-web/backups -xdev -maxdepth 1 -type f \( -name '.backup-*.tar.partial' -o -name 'backup-000[12].tar' \) -delete && systemctl reset-failed rescue-backup.service rescue-web.service && systemctl restart rescue-web.service"
bash ./lab verify 13

bash ./lab reset
for unit in rescue-backup.timer rescue-backup.service rescue-backup-volume.service; do
  if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
    systemctl cat "${unit}" >/dev/null 2>&1; then
    fail "lab reset left the incident 13 ${unit} unit behind"
  fi
done
if MSYS_NO_PATHCONV=1 docker exec lsr-relay \
  test -e /usr/local/bin/rescue-backup-run; then
  fail "lab reset left the incident 13 backup script behind"
fi
for drill in 01 02 03 04 05 06 07 08 09 10 11 12 13; do
  expect_no_active_drill "${drill}"
done

printf 'Smoke test passed for %s.\n' "${distro}"
