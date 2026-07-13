#!/usr/bin/env bash
set -Eeuo pipefail

readonly hosts_file="/etc/hosts"
readonly wrong_address="203.0.113.99"
readonly upstream_name="rescue-api.internal"
readonly marker="cloudsprocket-dns-ghost"

temporary_file="$(mktemp /run/rescue-hosts.XXXXXX)"
trap 'rm -f "${temporary_file}"' EXIT

awk -v marker="${marker}" 'index($0, marker) == 0' "${hosts_file}" > "${temporary_file}"
cat "${temporary_file}" > "${hosts_file}"
printf '%s %s # %s\n' "${wrong_address}" "${upstream_name}" "${marker}" >> "${hosts_file}"
