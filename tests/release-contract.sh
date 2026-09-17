#!/usr/bin/env bash
set -euo pipefail

workflow='.github/workflows/docker.publish.yml'

for contract in \
  'actions/checkout@v7' \
  'docker/setup-qemu-action@v4' \
  'docker/setup-buildx-action@v4' \
  'docker/login-action@v4' \
  'docker/metadata-action@v6' \
  'docker/build-push-action@v7' \
  'actions/attest@v4' \
  'release_tag:' \
  'MANUAL_RELEASE_TAG' \
  "releases/tags/\${MANUAL_RELEASE_TAG}" \
  'PUBLISH_RELEASE_TAG' \
  'Enforce immutable release tags' \
  'linux/amd64,linux/arm64' \
  'provenance: mode=max' \
  'sbom: true'; do
  grep -Fq "$contract" "$workflow"
done

grep -Fq "cron: '0 0 * * 0'" "$workflow"
grep -Fq 'types: [published]' "$workflow"

if grep -Fq 'actions/checkout@v4' "$workflow"; then
  echo 'Legacy checkout action detected.' >&2
  exit 1
fi
if grep -Fq 'docker/login-action@v3' "$workflow"; then
  echo 'Legacy Docker login action detected.' >&2
  exit 1
fi

echo 'Release workflow contracts passed.'
