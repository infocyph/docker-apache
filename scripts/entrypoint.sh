#!/bin/sh
set -eu

configure_timezone() {
  if [ -z "${TZ:-}" ]; then
    return 0
  fi

  if [ ! -f "/usr/share/zoneinfo/$TZ" ]; then
    echo "[entrypoint] Warning: timezone '$TZ' not found under /usr/share/zoneinfo; keeping current timezone" >&2
    return 0
  fi

  ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
  printf '%s\n' "$TZ" > /etc/timezone
}

configure_timezone

exec "$@"
