#!/usr/bin/env bash
set -euo pipefail

image="${1:-infocyph/apache:ci}"
name="apache-smoke-$$"

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run -d --name "$name" "$image" >/dev/null

for _ in $(seq 1 40); do
  status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null || true)"
  case "$status" in
    healthy) break ;;
    unhealthy)
      docker inspect --format '{{json .State.Health}}' "$name" >&2 || true
      docker logs "$name" >&2 || true
      exit 1
      ;;
  esac
  sleep 1
done

[ "$(docker inspect --format '{{.State.Health.Status}}' "$name")" = healthy ]

docker exec "$name" sh -ec '
  httpd -t
  /usr/local/bin/healthcheck
  command -v ab >/dev/null
  command -v htpasswd >/dev/null
  chromacat --version >/dev/null
'

docker stop --time 10 "$name" >/dev/null
[ "$(docker inspect --format '{{.State.ExitCode}}' "$name")" -eq 0 ]

echo 'Image smoke passed.'
