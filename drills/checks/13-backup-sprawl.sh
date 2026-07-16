#!/usr/bin/env bash
set -Eeuo pipefail

readonly drill_id="13-backup-sprawl"
readonly active_file="/var/lib/cloudsprocket-lab/active-drill"
readonly data_dir="/var/lib/rescue-web"
readonly backup_dir="${data_dir}/backups"
readonly backup_service="rescue-backup.service"
readonly backup_timer="rescue-backup.timer"
readonly web_service="rescue-web.service"

if [[ ! -f "${active_file}" ]]; then
  printf 'Nothing is broken. Start incident 13 with lab break 13.\n'
  exit 2
fi

active_drill="$(<"${active_file}")"
if [[ "${active_drill}" != "${drill_id}" ]]; then
  printf 'Incident %s is active, not %s.\n' "${active_drill}" "${drill_id}" >&2
  exit 2
fi

read_used_percent() {
  df -P "${data_dir}" | awk 'NR == 2 {gsub(/%/, "", $5); print $5}'
}

read_available_kib() {
  df -Pk "${data_dir}" | awk 'NR == 2 {print $4}'
}

read_backup_start() {
  systemctl show --property ExecMainStartTimestampMonotonic \
    --value "${backup_service}" 2>/dev/null || printf '0\n'
}

has_complete_backup() {
  find "${backup_dir}" -xdev -maxdepth 1 -type f \
    -name 'backup-*.tar' -print -quit | grep --quiet .
}

wait_for_completed_backup_after() {
  local previous_start="$1" current_start
  for _ in {1..80}; do
    current_start="$(read_backup_start)"
    if [[ -n "${current_start}" && "${current_start}" != "${previous_start}" ]] \
      && ! systemctl is-active --quiet "${backup_service}"; then
      systemctl is-failed --quiet "${backup_service}" && return 1
      printf '%s\n' "${current_start}"
      return 0
    fi
    sleep 0.25
  done
  return 1
}

check_health() {
  local response
  response="$(curl --fail --silent --connect-timeout 1 --max-time 2 \
    http://127.0.0.1:8080/health 2>/dev/null || true)"
  [[ "${response}" == *'"service": "rescue-web"'* ]]
}

used_before="$(read_used_percent)"
if (( used_before >= 90 )); then
  printf 'NOT FIXED: the rescue-web filesystem remains at %s%% use.\n' \
    "${used_before}" >&2
  exit 1
fi

probe="${data_dir}/.backup-space-probe"
if ! runuser --user rescue -- touch "${probe}" 2>/dev/null; then
  printf 'NOT FIXED: rescue-web still cannot create files in its data directory.\n' >&2
  exit 1
fi
rm -f "${probe}"

if ! has_complete_backup; then
  printf 'NOT FIXED: no complete backup was preserved.\n' >&2
  exit 1
fi

timer_active=0
timer_enabled=0
systemctl is-active --quiet "${backup_timer}" && timer_active=1
systemctl is-enabled --quiet "${backup_timer}" 2>/dev/null && timer_enabled=1
if (( timer_enabled == 1 && timer_active == 0 )); then
  printf 'NOT FIXED: the unsafe backup timer will return at the next boot.\n' >&2
  exit 1
fi

if ! systemctl is-enabled --quiet "${web_service}" \
  || ! systemctl is-active --quiet "${web_service}"; then
  printf 'NOT FIXED: rescue-web.service is not enabled or not active.\n' >&2
  exit 1
fi

if ! check_health; then
  printf 'NOT FIXED: rescue-web does not answer on port 8080.\n' >&2
  exit 1
fi

if (( timer_active == 1 )); then
  previous_start="$(read_backup_start)"
  previous_available=""
  stable_storage=0
  # Sample only after completed jobs, never while a valid archive is in flight.
  # Five samples allow a retention policy to reach a three-archive steady state
  # after the first completed job establishes an unambiguous baseline.
  for _ in {1..5}; do
    if ! current_start="$(wait_for_completed_backup_after "${previous_start}")"; then
      printf 'NOT FIXED: the active timer did not complete a healthy backup run.\n' >&2
      exit 1
    fi
    current_available="$(read_available_kib)"
    used_after="$(read_used_percent)"
    if (( used_after >= 90 )); then
      printf 'NOT FIXED: recurring backups filled the filesystem again.\n' >&2
      exit 1
    fi
    if [[ -n "${previous_available}" ]] \
      && (( current_available + 4096 >= previous_available )); then
      stable_storage=1
      break
    fi
    previous_start="${current_start}"
    previous_available="${current_available}"
  done
  if (( stable_storage == 0 )); then
    printf 'NOT FIXED: backup storage did not stabilise across completed timer runs.\n' >&2
    exit 1
  fi
else
  available_before="$(read_available_kib)"
  sleep 5
  available_after="$(read_available_kib)"
  used_after="$(read_used_percent)"
  if (( used_after >= 90 )); then
    printf 'NOT FIXED: recurring backups filled the filesystem again.\n' >&2
    exit 1
  fi
  if (( available_after + 4096 < available_before )); then
    printf 'NOT FIXED: backup growth resumed during the retention check.\n' >&2
    exit 1
  fi
fi

if ! has_complete_backup; then
  printf 'NOT FIXED: the retention policy did not preserve a complete backup.\n' >&2
  exit 1
fi

if ! systemctl is-active --quiet "${web_service}" || ! check_health; then
  printf 'NOT FIXED: rescue-web did not remain healthy during the retention check.\n' >&2
  exit 1
fi

printf 'PASS: backup growth is controlled and rescue-web remains healthy.\n'
