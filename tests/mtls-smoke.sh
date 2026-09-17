#!/usr/bin/env bash
set -euo pipefail

image="${1:-infocyph/apache:ci}"
network="apache-mtls-$$"
apache="apache-mtls-$$"
proxy="nginx-mtls-$$"
tmp="$(mktemp -d)"

cleanup() {
  docker rm -f "$proxy" "$apache" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp/mkcert" "$tmp/rootCA" "$tmp/app" "$tmp/vhosts"
printf 'mtls-ok\n' > "$tmp/app/index.html"

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=LocalDevStack Test Root' \
  -keyout "$tmp/ca.key" \
  -out "$tmp/rootCA/rootCA.pem" >/dev/null 2>&1

openssl req -newkey rsa:2048 -nodes \
  -subj '/CN=apache.test' \
  -keyout "$tmp/mkcert/lds-server-key.pem" \
  -out "$tmp/server.csr" >/dev/null 2>&1
printf '%s\n' 'subjectAltName=DNS:apache.test' 'extendedKeyUsage=serverAuth' > "$tmp/server.ext"
openssl x509 -req -days 1 \
  -in "$tmp/server.csr" \
  -CA "$tmp/rootCA/rootCA.pem" \
  -CAkey "$tmp/ca.key" \
  -CAcreateserial \
  -extfile "$tmp/server.ext" \
  -out "$tmp/mkcert/lds-server.pem" >/dev/null 2>&1

openssl req -newkey rsa:2048 -nodes \
  -subj '/CN=nginx-internal' \
  -keyout "$tmp/mkcert/lds-client-internal-key.pem" \
  -out "$tmp/client.csr" >/dev/null 2>&1
printf '%s\n' 'extendedKeyUsage=clientAuth' > "$tmp/client.ext"
openssl x509 -req -days 1 \
  -in "$tmp/client.csr" \
  -CA "$tmp/rootCA/rootCA.pem" \
  -CAkey "$tmp/ca.key" \
  -CAcreateserial \
  -extfile "$tmp/client.ext" \
  -out "$tmp/mkcert/lds-client-internal.pem" >/dev/null 2>&1

cat > "$tmp/vhosts/ssl.conf" <<'EOF'
<VirtualHost *:443>
    ServerName apache.test
    DocumentRoot /app
    SSLEngine on
    SSLCertificateFile /etc/mkcert/lds-server.pem
    SSLCertificateKeyFile /etc/mkcert/lds-server-key.pem
    SSLCACertificateFile /etc/share/rootCA/rootCA.pem
    SSLVerifyClient require
    SSLVerifyDepth 2
    SSLProtocol -all +TLSv1.2 +TLSv1.3
    Protocols h2 http/1.1
    <Directory "/app">
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

cat > "$tmp/nginx.conf" <<EOF
events {}
http {
  server {
    listen 8080;
    server_name _;
    location / {
      proxy_pass https://$apache:443;
      proxy_set_header Host apache.test;
      proxy_ssl_certificate /etc/mkcert/lds-client-internal.pem;
      proxy_ssl_certificate_key /etc/mkcert/lds-client-internal-key.pem;
      proxy_ssl_trusted_certificate /etc/share/rootCA/rootCA.pem;
      proxy_ssl_verify on;
      proxy_ssl_verify_depth 2;
      proxy_ssl_server_name on;
      proxy_ssl_name apache.test;
    }
  }
}
EOF

docker network create "$network" >/dev/null

docker run -d --name "$apache" --network "$network" \
  -v "$tmp/app:/app:ro" \
  -v "$tmp/vhosts/ssl.conf:/usr/local/apache2/conf/vhosts/ssl.conf:ro" \
  -v "$tmp/mkcert:/etc/mkcert:ro" \
  -v "$tmp/rootCA:/etc/share/rootCA:ro" \
  "$image" >/dev/null

for _ in $(seq 1 40); do
  status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$apache" 2>/dev/null || true)"
  [[ "$status" == healthy ]] && break
  if [[ "$status" == unhealthy ]]; then
    docker inspect --format '{{json .State.Health}}' "$apache" >&2 || true
    docker logs "$apache" >&2 || true
    exit 1
  fi
  sleep 1
done
[[ "$(docker inspect --format '{{.State.Health.Status}}' "$apache")" == healthy ]]

docker run -d --name "$proxy" --network "$network" \
  -v "$tmp/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$tmp/mkcert:/etc/mkcert:ro" \
  -v "$tmp/rootCA:/etc/share/rootCA:ro" \
  nginx:alpine >/dev/null

response=''
for _ in $(seq 1 30); do
  if response="$(docker exec "$proxy" wget -qO- http://127.0.0.1:8080/ 2>/dev/null)"; then
    break
  fi
  sleep 1
done

if [[ "$response" != 'mtls-ok' ]]; then
  docker logs "$proxy" >&2 || true
  docker logs "$apache" >&2 || true
  echo "Unexpected mTLS response: $response" >&2
  exit 1
fi

echo 'Nginx -> Apache backend mTLS smoke passed.'
