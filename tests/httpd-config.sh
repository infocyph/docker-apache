#!/usr/bin/env bash
set -euo pipefail

image="${1:-infocyph/apache:ci}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tcp_vhost="$repo_root/tests/fixtures/vhosts/php-fpm.conf"
socket_vhost="$repo_root/tests/fixtures/vhosts/php-fpm-socket.conf"

docker run --rm "$image" sh -ec '
  httpd -t
  httpd -M > /tmp/modules
  for module in proxy_module proxy_fcgi_module setenvif_module rewrite_module ssl_module socache_shmcb_module headers_module deflate_module http2_module; do
    grep -Fq " ${module} (shared)" /tmp/modules
  done

  apk info -e apache2-utils >/dev/null
  ! apk info -e apache2 >/dev/null 2>&1
  ! apk info -e apache-mod-fcgid >/dev/null 2>&1
  command -v ab >/dev/null
  command -v htpasswd >/dev/null

  conf=/usr/local/apache2/conf/httpd.conf
  for directive in \
    "ServerName \${SERVER_NAME}" \
    "ServerTokens Prod" \
    "ServerSignature Off" \
    "TraceEnable Off" \
    "ProxyRequests Off" \
    "IncludeOptional conf/vhosts/*.conf"; do
    test "$(grep -Fxc "$directive" "$conf")" -eq 1
  done

  before="$(sha256sum "$conf")"
  /usr/local/bin/update_httpd.sh
  once="$(sha256sum "$conf")"
  /usr/local/bin/update_httpd.sh
  twice="$(sha256sum "$conf")"
  test "$before" = "$once"
  test "$once" = "$twice"
'

for vhost in "$tcp_vhost" "$socket_vhost"; do
  docker run --rm --entrypoint sh \
    -v "$vhost:/usr/local/apache2/conf/vhosts/php.conf:ro" \
    "$image" -ec 'httpd -t'
done

docker run --rm \
  -e SERVER_NAME=runtime.apache.test \
  -e APACHE_LOG_DIR=/tmp/apache-runtime-logs \
  "$image" sh -ec '
    test "$SERVER_NAME" = runtime.apache.test
    test "$APACHE_LOG_DIR" = /tmp/apache-runtime-logs
    test -d "$APACHE_LOG_DIR"
    test -w "$APACHE_LOG_DIR"
    httpd -t
  '

docker run --rm -e TZ=Invalid/Zone "$image" sh -ec 'httpd -t'
docker run --rm "$image" sh -ec 'test "$(printf ok)" = ok'

echo 'Apache configuration contracts passed.'
