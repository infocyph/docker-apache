#!/bin/sh
set -eu

HTTPD_CONF="/usr/local/apache2/conf/httpd.conf"

lines_to_update="
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so
LoadModule setenvif_module modules/mod_setenvif.so
LoadModule rewrite_module modules/mod_rewrite.so
LoadModule ssl_module modules/mod_ssl.so
LoadModule socache_shmcb_module modules/mod_socache_shmcb.so
LoadModule headers_module modules/mod_headers.so
LoadModule deflate_module modules/mod_deflate.so
ServerName ${SERVER_NAME}
SSLSessionCache shmcb:/usr/local/apache2/logs/ssl_scache(512000)
SSLSessionCacheTimeout 86400
Listen 80
Listen 443
IncludeOptional conf/extra/*.conf
"

escape_sed_re() {
    # Escape sed BRE meta chars + delimiter-sensitive chars.
    # Covers: . [ ] * ^ $ \ ( ) { } + ? | and also / &
    printf '%s' "$1" | sed 's/[.[\*^$\\(){}+?|]/\\&/g; s/[\/&]/\\&/g'
}

ensure_line() {
    line="$1"

    # If line exists commented or uncommented, normalize it to exactly the active form.
    re="$(escape_sed_re "$line")"

    if grep -Fqx "$line" "$HTTPD_CONF"; then
        return 0
    fi

    # Replace a commented match (allow leading whitespace + # + whitespace)
    if grep -Eq "^[[:space:]]*#[[:space:]]*${re}[[:space:]]*$" "$HTTPD_CONF"; then
        # Use a regex that matches the whole line and rewrites to the exact desired line.
        sed -i "s|^[[:space:]]*#[[:space:]]*${re}[[:space:]]*$|$line|g" "$HTTPD_CONF"
        return 0
    fi

    # Otherwise append
    printf '%s\n' "$line" >> "$HTTPD_CONF"
}

# Process each desired configuration line.
printf '%s\n' "$lines_to_update" | while IFS= read -r config_line; do
    [ -z "$config_line" ] && continue
    ensure_line "$config_line"
done

echo "Apache configuration updated successfully."
