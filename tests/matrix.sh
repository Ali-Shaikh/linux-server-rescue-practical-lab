#!/usr/bin/env bash
set -Eeuo pipefail

readonly root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root_dir}"

for distro in ubuntu debian rocky; do
  printf '\n=== Testing %s ===\n' "${distro}"
  bash ./tests/smoke.sh "${distro}"
done

printf '\nDistribution matrix passed.\n'
