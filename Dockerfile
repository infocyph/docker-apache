FROM httpd:alpine

LABEL org.opencontainers.image.source="https://github.com/infocyph/docker-apache"
LABEL org.opencontainers.image.description="Apache"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="infocyph,abmmhasan"

ENV APACHE_LOG_DIR=/var/log/apache2
ENV SERVER_NAME=localhost
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN set -eux; \
    apk add --no-cache \
      apache2-utils apache-mod-fcgid tzdata bash figlet ncurses musl-locales gawk curl ca-certificates; \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

# Prefer COPY (vendored) over remote ADD.
# If you must download, pin to a commit/tag.
RUN set -eux; \
    curl -fsSL "https://raw.githubusercontent.com/infocyph/Scriptomatic/master/bash/banner.sh" -o /usr/local/bin/show-banner; \
    curl -fsSL "https://raw.githubusercontent.com/infocyph/Toolset/main/ChromaCat/chromacat" -o /usr/local/bin/chromacat; \
    chmod +x /usr/local/bin/show-banner /usr/local/bin/chromacat

COPY scripts/update_httpd.sh /usr/local/bin/update_httpd.sh
RUN set -eux; \
    chmod +x /usr/local/bin/update_httpd.sh; \
    /usr/local/bin/update_httpd.sh; \
    rm -f /usr/local/bin/update_httpd.sh; \
    mkdir -p /etc/profile.d; \
    { \
      echo '#!/bin/sh'; \
      echo 'if [ -n "$PS1" ] && [ -z "${BANNER_SHOWN-}" ]; then'; \
      echo '  export BANNER_SHOWN=1'; \
      echo "  APACHE_VERSION=\$(httpd -v | sed -n 's|^Server version: Apache/\\([0-9.]*\\).*|\\1|p')"; \
      echo '  show-banner "APACHE $APACHE_VERSION"'; \
      echo 'fi'; \
    } > /etc/profile.d/banner-hook.sh; \
    chmod +x /etc/profile.d/banner-hook.sh; \
    echo 'source /etc/profile.d/banner-hook.sh 2>/dev/null || true' >> /root/.bashrc

WORKDIR /app
EXPOSE 80 443
CMD ["httpd-foreground"]
