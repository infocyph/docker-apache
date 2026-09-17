#!/usr/bin/env bash
set -euo pipefail

image="${1:-infocyph/apache:ci}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
static_vhost="$repo_root/tests/fixtures/vhosts/static.conf"
ssl_vhost="$repo_root/tests/fixtures/vhosts/ssl.conf"

wait_healthy() {
  local name="$1" status
  for _ in $(seq 1 40); do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null || true)"
    case "$status" in
      healthy) return 0 ;;
      unhealthy)
        docker inspect --format '{{json .State.Health}}' "$name" >&2 || true
        docker logs "$name" >&2 || true
        return 1
        ;;
    esac
    sleep 1
  done
  docker logs "$name" >&2 || true
  return 1
}

name="apache-health-static-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT INT TERM

docker run -d --name "$name" \
  -v "$static_vhost:/usr/local/apache2/conf/vhosts/static.conf:ro" \
  "$image" >/dev/null
wait_healthy "$name"
docker rm -f "$name" >/dev/null

docker run --rm --entrypoint sh "$image" -ec '
  if /usr/local/bin/healthcheck >/tmp/health.out 2>&1; then
    echo "healthcheck unexpectedly passed without Apache running" >&2
    exit 1
  fi
  grep -Fq "Apache HTTP listener is unreachable" /tmp/health.out
'

docker run --rm --entrypoint sh \
  -v "$ssl_vhost:/usr/local/apache2/conf/vhosts/ssl.conf:ro" \
  "$image" -ec '
    if /usr/local/bin/healthcheck >/tmp/health.out 2>&1; then
      echo "healthcheck unexpectedly passed with missing TLS inputs" >&2
      exit 1
    fi
    grep -Eq "Apache configuration is invalid|Required TLS file is missing or unreadable" /tmp/health.out
  '

echo 'Healthcheck contracts passed.'
