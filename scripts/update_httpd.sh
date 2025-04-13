#!/bin/sh
set -e

HTTPD_CONF="/usr/local/apache2/conf/httpd.conf"

# Define the list of configuration lines to check/update.
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

# Function to process one configuration line.
process_line() {
    line="$1"
    escaped_line=$(printf '%s\n' "$line" | sed 's/[\/&]/\\&/g')
    sed -i "s/^#\s*\(${escaped_line}\)/\1/" "$HTTPD_CONF"
    if ! grep -Fq "$line" "$HTTPD_CONF"; then
        echo "$line" >> "$HTTPD_CONF"
    fi
}

# Process each desired configuration line.
echo "$lines_to_update" | while IFS= read -r config_line; do
    [ -z "$config_line" ] && continue
    process_line "$config_line"
done

echo "Apache configuration updated successfully."

rm -f -- "$0"