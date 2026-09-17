#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for script in scripts/*.sh; do
  sh -n "$script"
done

for test_script in tests/*.sh; do
  bash -n "$test_script"
done

shellcheck scripts/*.sh tests/*.sh

grep -Fq 'FROM httpd:alpine' Dockerfile
grep -Fq 'apache2-utils' Dockerfile
! grep -Fq 'apache-mod-fcgid' Dockerfile
! grep -Eq '^[[:space:]]*apache2([[:space:]\\]|$)' Dockerfile
grep -Fq 'Scriptomatic/main/bash/banner.sh' Dockerfile
grep -Fq 'Toolset/releases/latest/download/install.sh' Dockerfile

grep -Fq 'ServerName ${SERVER_NAME}' scripts/update_httpd.sh
for directive in \
  'ServerTokens Prod' \
  'ServerSignature Off' \
  'TraceEnable Off' \
  'ProxyRequests Off' \
  'IncludeOptional conf/vhosts/*.conf'; do
  grep -Fq "$directive" scripts/update_httpd.sh
done

if grep -Eq '^[[:space:]]*(Include|IncludeOptional)[[:space:]]+conf/extra/\\\\\*\\.conf' scripts/update_httpd.sh; then
  echo 'update_httpd.sh must not remove broad upstream conf/extra includes' >&2
  exit 1
fi

echo 'Static checks passed.'
