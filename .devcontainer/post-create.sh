#!/usr/bin/env bash
set -Eeuo pipefail

readonly root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly max_attempts=60

cd "${root_dir}"

docker_ready=false
for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  if docker info >/dev/null 2>&1; then
    docker_ready=true
    break
  fi
  sleep 1
done

if [[ "${docker_ready}" != "true" ]]; then
  printf 'Docker-in-Docker did not become ready within %s seconds.\n' "${max_attempts}" >&2
  exit 1
fi

docker compose version
docker compose --project-name lsr --file compose.yaml config --quiet
bash ./lab doctor ubuntu

printf '\nCodespaces is ready. Start with: ./lab up ubuntu\n'
printf 'The lab is not started automatically, so you control image downloads and usage.\n'
