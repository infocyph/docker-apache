#!/bin/sh
set -eu

HTTPD_ROOT="/usr/local/apache2"
HTTPD_CONF="$HTTPD_ROOT/conf/httpd.conf"

fail() {
    printf '[update-httpd] %s\n' "$*" >&2
    exit 1
}

[ -r "$HTTPD_CONF" ] || fail "Apache configuration is not readable: $HTTPD_CONF"

ensure_line() {
    wanted="$1"
    tmp="$(mktemp)"

    awk -v wanted="$wanted" '
        BEGIN { found = 0 }
        {
            candidate = $0
            sub(/^[[:space:]]*/, "", candidate)
            if (substr(candidate, 1, 1) == "#") {
                sub(/^#[[:space:]]*/, "", candidate)
            }
            sub(/[[:space:]]*$/, "", candidate)

            if (candidate == wanted) {
                if (!found) {
                    print wanted
                    found = 1
                }
                next
            }

            print
        }
        END {
            if (!found) {
                print wanted
            }
        }
    ' "$HTTPD_CONF" > "$tmp" || {
        rm -f "$tmp"
        fail "Unable to update Apache configuration"
    }

    cat "$tmp" > "$HTTPD_CONF"
    rm -f "$tmp"
}

while IFS='|' read -r module path; do
    [ -n "$module" ] || continue
    [ -f "$HTTPD_ROOT/$path" ] || fail "Required Apache module file is missing: $path"
    ensure_line "LoadModule $module $path"
done <<'EOF'
proxy_module|modules/mod_proxy.so
proxy_fcgi_module|modules/mod_proxy_fcgi.so
setenvif_module|modules/mod_setenvif.so
rewrite_module|modules/mod_rewrite.so
ssl_module|modules/mod_ssl.so
socache_shmcb_module|modules/mod_socache_shmcb.so
headers_module|modules/mod_headers.so
deflate_module|modules/mod_deflate.so
http2_module|modules/mod_http2.so
EOF

while IFS= read -r directive; do
    [ -n "$directive" ] || continue
    ensure_line "$directive"
done <<'EOF'
ServerName ${SERVER_NAME}
ServerTokens Prod
ServerSignature Off
TraceEnable Off
ProxyRequests Off
SSLSessionCache shmcb:/usr/local/apache2/logs/ssl_scache(512000)
SSLSessionCacheTimeout 86400
Listen 80
Listen 443
IncludeOptional conf/vhosts/*.conf
EOF

if ! httpd -t >/dev/null 2>&1; then
    httpd -t >&2 || true
    fail "Apache configuration validation failed"
fi
