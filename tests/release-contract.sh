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
  'Snapshot rolling upstream inputs' \
  'retry get_httpd_digest' \
  'retry get_scriptomatic_sha' \
  'retry get_toolset_release' \
  "HTTPD_ALPINE_REF=httpd:alpine@\${{ env.HTTPD_ALPINE_DIGEST }}" \
  "SCRIPTOMATIC_REF=\${{ env.SCRIPTOMATIC_MAIN_SHA }}" \
  "TOOLSET_RELEASE=\${{ env.TOOLSET_RELEASE }}" \
  "TOOLSET_INSTALLER_SHA256=\${{ env.TOOLSET_INSTALLER_SHA256 }}" \
  'linux/amd64,linux/arm64' \
  'provenance: mode=max' \
  'sbom: true'; do
  grep -Fq "$contract" "$workflow"
done

grep -Fq "cron: '0 0 * * 0'" "$workflow"
grep -Fq 'types: [published]' "$workflow"

for pinned_contract in \
  'HTTPD_ALPINE_REF=httpd:alpine@${{ env.HTTPD_ALPINE_DIGEST }}' \
  'SCRIPTOMATIC_REF=${{ env.SCRIPTOMATIC_MAIN_SHA }}' \
  'TOOLSET_RELEASE=${{ env.TOOLSET_RELEASE }}' \
  'TOOLSET_INSTALLER_SHA256=${{ env.TOOLSET_INSTALLER_SHA256 }}'; do
  pinned_builds="$(grep -cF "$pinned_contract" "$workflow")"
  if [[ "$pinned_builds" -ne 3 ]]; then
    echo "Expected all three publish builds to use pinned input: $pinned_contract; found $pinned_builds." >&2
    exit 1
  fi
done

if grep -Fq 'Revalidate rolling upstreams before publish' "$workflow"; then
  echo 'Publish workflow must not re-resolve mutable upstreams after immutable snapshotting.' >&2
  exit 1
fi
if grep -Fq 'imagetools inspect httpd:alpine | awk' "$workflow"; then
  echo 'Unsafe pipefail-sensitive httpd digest pipeline detected.' >&2
  exit 1
fi
if grep -Fq 'Scriptomatic.git refs/heads/main | awk' "$workflow"; then
  echo 'Unsafe pipefail-sensitive Scriptomatic revision pipeline detected.' >&2
  exit 1
fi
if grep -Fq 'Toolset/releases/latest/download/install.sh' "$workflow"; then
  echo 'Publish workflow must checksum an exact Toolset release installer.' >&2
  exit 1
fi

if grep -Fq 'actions/checkout@v4' "$workflow"; then
  echo 'Legacy checkout action detected.' >&2
  exit 1
fi
if grep -Fq 'docker/login-action@v3' "$workflow"; then
  echo 'Legacy Docker login action detected.' >&2
  exit 1
fi

echo 'Release workflow contracts passed.'
