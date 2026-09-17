#!/usr/bin/env bash
set -euo pipefail

image="${1:-infocyph/apache:ci}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bash tests/image-smoke.sh "$image"
bash tests/httpd-config.sh "$image"
bash tests/healthcheck.sh "$image"
bash tests/mtls-smoke.sh "$image"

echo 'Apache release gate passed.'
