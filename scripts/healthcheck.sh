#!/bin/sh
set -eu

HTTPD_CONF="/usr/local/apache2/conf/httpd.conf"
VHOST_DIR="/usr/local/apache2/conf/vhosts"

[ -r "$HTTPD_CONF" ]
[ -d "$VHOST_DIR" ]

httpd -t >/dev/null 2>&1

if find "$VHOST_DIR" -type f -name '*.conf' -print -quit 2>/dev/null | grep -q .; then
  if grep -Rq 'SSLEngine[[:space:]]\+on' "$VHOST_DIR" 2>/dev/null; then
    [ -f /etc/mkcert/apache-server.pem ]
    [ -f /etc/mkcert/apache-server-key.pem ]
  fi

  curl -sS -o /dev/null http://127.0.0.1/
fi

exit 0