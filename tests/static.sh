#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'Static contract failed: %s\n' "$*" >&2
  exit 1
}

for script in scripts/*.sh; do
  sh -n "$script"
done

for test_script in tests/*.sh; do
  bash -n "$test_script"
done

shellcheck scripts/*.sh tests/*.sh

grep -Fq 'FROM httpd:alpine' Dockerfile
grep -Fq 'apache2-utils' Dockerfile
if grep -Fq 'apache-mod-fcgid' Dockerfile; then
  fail 'apache-mod-fcgid must not be installed'
fi
if grep -Eq '^[[:space:]]+apache2([[:space:]\\]|$)' Dockerfile; then
  fail 'Alpine apache2 server package must not be installed'
fi
grep -Fq 'Scriptomatic/main/bash/banner.sh' Dockerfile
grep -Fq 'Toolset/releases/latest/download/install.sh' Dockerfile

grep -Fq "ServerName \${SERVER_NAME}" scripts/update_httpd.sh
for directive in \
  'ServerTokens Prod' \
  'ServerSignature Off' \
  'TraceEnable Off' \
  'ProxyRequests Off' \
  'IncludeOptional conf/vhosts/*.conf'; do
  grep -Fq "$directive" scripts/update_httpd.sh
done

if grep -Fq 'conf/extra' scripts/update_httpd.sh; then
  fail 'update_httpd.sh must not rewrite broad upstream conf/extra configuration'
fi
if grep -Fq "rm -f -- \"\$0\"" scripts/update_httpd.sh; then
  fail 'update_httpd.sh must remain available in the final image'
fi

grep -Fq 'exec "$@"' scripts/entrypoint.sh
grep -Fq '127.0.0.1' scripts/healthcheck.sh
grep -Fq -- '--connect-timeout' scripts/healthcheck.sh
grep -Fq -- '--max-time' scripts/healthcheck.sh

grep -Fq 'infocyph/apache:latest' README.md
if grep -Fq 'infocyph/docker-apache:' README.md; then
  fail 'README must use the published infocyph/apache image name'
fi
grep -Fq '`SERVER_NAME`' README.md
grep -Fq '`APACHE_LOG_DIR`' README.md
grep -Fq '`apache2-utils`' README.md

bash tests/release-contract.sh

echo 'Static checks passed.'
