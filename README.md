# docker-apache

A custom **Apache HTTP Server** Docker image built on top of the lightweight [`httpd:alpine`](https://hub.docker.com/_/httpd).  
It ships with a small config updater that enables commonly needed modules (proxy/FCGI, SSL, rewrite, headers, etc.) and applies a few sane defaults.

---

## Features

- **Small footprint**: based on `httpd:alpine`
- **Auto configuration**: enables essential modules and settings on build
  - `mod_proxy`, `mod_proxy_fcgi`
  - `mod_rewrite`
  - `mod_ssl` + `socache_shmcb`
  - `mod_headers`, `mod_deflate`
- **Timezone support** via `tzdata` + `TZ` env
- **Nice interactive banner** when you open a shell inside the container (optional convenience)

---

## Quick Start

### Build

```bash
docker build -t infocyph/docker-apache:latest .
````

### Run

```bash
docker run -d \
  --name apache \
  -p 80:80 -p 443:443 \
  -e TZ=Asia/Dhaka \
  -e SERVER_NAME=localhost \
  infocyph/docker-apache:latest
```

---

## Environment Variables

| Variable         |            Default | Description                                        |
| ---------------- | -----------------: | -------------------------------------------------- |
| `TZ`             |          *(empty)* | Container timezone (example: `Asia/Dhaka`)         |
| `SERVER_NAME`    |        `localhost` | Apache `ServerName` used by the config updater     |
| `APACHE_LOG_DIR` | `/var/log/apache2` | Log directory path (mount if you want persistence) |

> Note: `SERVER_NAME` is applied by the build-time config updater in the current image design.

---

## Logs (optional)

To persist logs on the host:

```bash
docker run -d \
  --name apache \
  -p 80:80 -p 443:443 \
  -v "$(pwd)/logs:/var/log/apache2" \
  infocyph/docker-apache:latest
```

---

## Validate Inside the Container

```bash
docker exec -it apache sh -lc 'httpd -v && httpd -M | head'
```

---

## License

MIT — see [MIT License](https://opensource.org/licenses/MIT).
