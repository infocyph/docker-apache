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
  'PUBLISH_RELEASE_TAG' \
  'Enforce immutable release tags' \
  'linux/amd64,linux/arm64' \
  'provenance: mode=max' \
  'sbom: true'; do
  grep -Fq "$contract" "$workflow"
done

grep -Fq "cron: '0 0 * * 0'" "$workflow"
! grep -Fq 'actions/checkout@v4' "$workflow"
! grep -Fq 'docker/login-action@v3' "$workflow"

echo 'Release workflow contracts passed.'
