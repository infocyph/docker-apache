# docker-apache

[![Check](https://github.com/infocyph/docker-apache/actions/workflows/check.yml/badge.svg)](https://github.com/infocyph/docker-apache/actions/workflows/check.yml)
[![Docker Publish](https://github.com/infocyph/docker-apache/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-apache/actions/workflows/docker.publish.yml)
![Docker Pulls](https://img.shields.io/docker/pulls/infocyph/apache)
![Docker Image Size](https://img.shields.io/docker/image-size/infocyph/apache)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Hardened Apache HTTP Server image for LocalDevStack, built on the rolling official `httpd:alpine` base.

Apache is an **optional backend** for projects that require Apache semantics. Nginx remains the LocalDevStack edge/router; Apache serves generated vhosts and forwards PHP requests to PHP-FPM with `mod_proxy_fcgi`.

## Runtime contract

- Official rolling base: `httpd:alpine`
- Published images:
  - `docker.io/infocyph/apache`
  - `ghcr.io/infocyph/apache`
- Project root: `/app`
- Generated vhosts: `/usr/local/apache2/conf/vhosts/*.conf`
- Default log directory: `/var/log/apache2`
- Listeners: `80`, `443`
- Main process: `httpd-foreground`

The image enables the Apache modules LocalDevStack needs for proxy/FCGI, rewrite, headers, compression, TLS and HTTP/2. PHP-FPM uses `mod_proxy_fcgi`; `mod_fcgid` is intentionally not installed.

`apache2-utils` is intentionally retained for utilities such as `ab` and `htpasswd`, including future LocalDevStack/debugging use. The Alpine `apache2` server package itself is not installed, so the image contains only the official `/usr/local/apache2` runtime.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `TZ` | `Asia/Dhaka` | Container timezone. Invalid values are non-fatal and produce a warning. |
| `SERVER_NAME` | `localhost` | Runtime Apache `ServerName`; evaluated when Apache starts. |
| `APACHE_LOG_DIR` | `/var/log/apache2` | Runtime log directory used by generated vhosts. |

Example:

```bash
docker run --rm \
  -e TZ=Asia/Dhaka \
  -e SERVER_NAME=example.localhost \
  -e APACHE_LOG_DIR=/var/log/apache2 \
  infocyph/apache:latest \
  httpd -t
```

## LocalDevStack mounts

A normal LocalDevStack Apache service mounts project data and generated configuration rather than generating them inside this image:

```text
/app                                      project source
/usr/local/apache2/conf/vhosts            generated Apache vhosts (read-only)
/etc/mkcert                               LocalDevStack server certificates (read-only)
/etc/share/rootCA                         LocalDevStack CA material (read-only)
/run/php-fpm                              shared PHP-FPM sockets when socket mode is used
/var/log/apache2                          Apache logs
```

Both PHP-FPM generator forms are supported:

```apache
SetHandler "proxy:fcgi://php-service:9000"
```

and:

```apache
SetHandler "proxy:unix:/run/php-fpm/example.sock|fcgi://localhost/"
```

## Backend TLS / mTLS

LocalDevStack may proxy HTTPS from Nginx to Apache using backend mTLS. The image supports the generated contract where Apache presents the LocalDevStack server certificate and requires a client certificate signed by the mounted LocalDevStack CA.

The repository release gate creates ephemeral certificates and proves a real Nginx -> Apache mTLS request. No private certificate material is stored in this repository or baked into the image.

## Healthcheck

The Docker healthcheck verifies:

1. Apache configuration is valid;
2. the generated-vhost directory exists;
3. TLS files referenced by mounted vhosts are readable;
4. Apache is actually reachable on `127.0.0.1:80` within bounded timeouts.

Health is about Apache/runtime reachability, not application response semantics. A redirect, authentication response or `404` can still prove the listener is healthy.

Inspect health diagnostics with:

```bash
docker inspect --format '{{json .State.Health}}' APACHE
docker exec APACHE /usr/local/bin/healthcheck
```

## Standalone smoke

The image is primarily intended for LocalDevStack, but a minimal standalone smoke is useful for debugging:

```bash
docker run -d --name apache-smoke -p 8080:80 infocyph/apache:latest
curl -I http://127.0.0.1:8080/
docker exec apache-smoke httpd -t
docker exec apache-smoke httpd -M
docker rm -f apache-smoke
```

## Included utilities

Interactive shells include the shared Infocyph Scriptomatic banner and ChromaCat tooling. `ab` and `htpasswd` are provided by `apache2-utils`.

Useful checks:

```bash
httpd -v
httpd -t
httpd -M
ab -V
htpasswd -h
chromacat --version
```

## Release model

Published version tags are immutable. A GitHub release publishes its exact version tag plus `latest` to Docker Hub and GHCR.

Scheduled/manual refreshes rebuild **only `latest`** from the most recent stable published source so the rolling `httpd:alpine`, Scriptomatic `main`, and Toolset `latest` inputs can receive compatible upstream updates without rewriting a historical version tag.

Before publication, CI/release gates verify amd64 and arm64 builds, configuration idempotency, PHP-FPM TCP/socket syntax, listener health, read-only mounts, Nginx -> Apache mTLS, package inventory, vulnerability status and clean process shutdown.

## License

MIT — see [LICENSE](LICENSE).
