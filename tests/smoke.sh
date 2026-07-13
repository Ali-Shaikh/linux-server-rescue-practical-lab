#!/usr/bin/env bash
set -Eeuo pipefail

readonly root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly distro="${1:-ubuntu}"
cd "${root_dir}"

cleanup() {
  LAB_DISTRO="${distro}" docker compose --project-name lsr --file compose.yaml \
    down --volumes --remove-orphans >/dev/null 2>&1 || true
}
cleanup
trap cleanup EXIT

bash ./lab doctor "${distro}"
bash ./lab up "${distro}"

actual_distro="$(MSYS_NO_PATHCONV=1 docker exec lsr-relay sh -c '. /etc/os-release; printf %s "$ID"')"
if [[ "${actual_distro}" != "${distro}" ]]; then
  printf 'Expected distribution %s, container reports %s.\n' "${distro}" "${actual_distro}" >&2
  exit 1
fi

set +e
bash ./lab verify 01
verify_code=$?
set -e
if [[ ${verify_code} -ne 2 ]]; then
  printf 'Expected verify on a healthy lab to return 2, got %s.\n' "${verify_code}" >&2
  exit 1
fi

bash ./lab break 01
if bash ./lab verify 01; then
  printf 'Expected the broken service to fail verification.\n' >&2
  exit 1
fi

MSYS_NO_PATHCONV=1 docker exec lsr-relay bash -c \
  "printf '[Service]\\nEnvironment=APP_PORT=8080\\n' > /etc/systemd/system/rescue-web.service.d/override.conf && systemctl daemon-reload && systemctl restart rescue-web.service"

bash ./lab verify 01
bash ./lab break 01
bash ./lab verify 01

bash ./lab reset
set +e
bash ./lab verify 01
verify_code=$?
set -e
if [[ ${verify_code} -ne 2 ]]; then
  printf 'Expected reset to clear drill state, got verify exit %s.\n' "${verify_code}" >&2
  exit 1
fi

printf 'Smoke test passed for %s.\n' "${distro}"
