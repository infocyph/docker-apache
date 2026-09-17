#!/bin/sh
set -eu

HTTPD_CONF="/usr/local/apache2/conf/httpd.conf"
VHOST_DIR="/usr/local/apache2/conf/vhosts"
SERVER_NAME="${SERVER_NAME:-localhost}"
APACHE_LOG_DIR="${APACHE_LOG_DIR:-/var/log/apache2}"
export SERVER_NAME APACHE_LOG_DIR

fail() {
    printf '[healthcheck] %s\n' "$*" >&2
    exit 1
}

[ -r "$HTTPD_CONF" ] || fail "Apache configuration is not readable"
[ -d "$VHOST_DIR" ] || fail "Apache vhost directory is missing"

if ! httpd -t >/dev/null 2>&1; then
    fail "Apache configuration is invalid"
fi

for tls_file in \
    /etc/mkcert/lds-server.pem \
    /etc/mkcert/lds-server-key.pem \
    /etc/share/rootCA/rootCA.pem; do
    if grep -RqF "$tls_file" "$VHOST_DIR" 2>/dev/null && [ ! -r "$tls_file" ]; then
        fail "Required TLS file is missing or unreadable: $tls_file"
    fi
done

if ! curl \
    --silent \
    --show-error \
    --output /dev/null \
    --noproxy '*' \
    --connect-timeout 2 \
    --max-time 4 \
    http://127.0.0.1/; then
    fail "Apache HTTP listener is unreachable on 127.0.0.1:80"
fi
