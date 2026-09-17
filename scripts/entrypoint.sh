#!/bin/sh
set -eu

SERVER_NAME="${SERVER_NAME:-localhost}"
APACHE_LOG_DIR="${APACHE_LOG_DIR:-/var/log/apache2}"
export SERVER_NAME APACHE_LOG_DIR

configure_timezone() {
    if [ -z "${TZ:-}" ]; then
        return 0
    fi

    if [ ! -f "/usr/share/zoneinfo/$TZ" ]; then
        printf "[entrypoint] Warning: timezone '%s' not found under /usr/share/zoneinfo; keeping current timezone\n" "$TZ" >&2
        return 0
    fi

    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    printf '%s\n' "$TZ" > /etc/timezone
}

configure_log_dir() {
    if ! mkdir -p "$APACHE_LOG_DIR"; then
        printf '[entrypoint] Error: unable to create Apache log directory: %s\n' "$APACHE_LOG_DIR" >&2
        exit 1
    fi

    if [ ! -d "$APACHE_LOG_DIR" ] || [ ! -w "$APACHE_LOG_DIR" ]; then
        printf '[entrypoint] Error: Apache log directory is not writable: %s\n' "$APACHE_LOG_DIR" >&2
        exit 1
    fi
}

configure_timezone
configure_log_dir

exec "$@"
