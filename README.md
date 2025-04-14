# docker-apache

This repository provides a custom Apache Docker image based on the lightweight [httpd:alpine](https://hub.docker.com/_/httpd) image. It includes an automated configuration update script that ensures necessary Apache modules and settings are enabled.

## Features

- **Lightweight Base Image:** Built on the `httpd:alpine` image for a small footprint.
- **Automated Configuration:** Uses `update_httpd.sh` to enable essential modules such as proxy, SSL, rewrite and more.
- **Flexible Setup:** Listens on ports 80 and 443 and sets the server name using an environment variable.

## Usage

1. **Build the Image:**

   ```bash
   docker build -t docker-apache .
   ```
2. **Run the Container:**

   ```bash
   docker run -d -p 80:80 -p 443:443 docker-apache
   ```

## Customization

- **Logging:** The Apache log directory is set to `/var/log/apache2`, which you may mount as a volume if needed.

## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).
