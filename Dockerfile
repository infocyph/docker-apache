FROM httpd:alpine

LABEL org.opencontainers.image.source="https://github.com/infocyph/docker-apache"
LABEL org.opencontainers.image.description="Hardened LocalDevStack Apache backend with PHP-FPM, TLS and HTTP/2 support"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="infocyph,abmmhasan"

ARG TZ=Asia/Dhaka

ENV APACHE_LOG_DIR=/var/log/apache2 \
    SERVER_NAME=localhost \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=${TZ}

RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache \
        apache2-utils \
        tzdata \
        bash \
        figlet \
        ncurses \
        musl-locales \
        gawk \
        curl \
        ca-certificates; \
    update-ca-certificates; \
    mkdir -p \
        /etc/profile.d \
        /usr/local/apache2/conf/vhosts \
        "$APACHE_LOG_DIR"; \
    chmod 0755 "$APACHE_LOG_DIR"

COPY scripts/update_httpd.sh /usr/local/bin/update_httpd.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck

RUN set -eux; \
    curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 \
      "https://raw.githubusercontent.com/infocyph/Scriptomatic/main/bash/banner.sh" \
      -o /usr/local/bin/show-banner; \
    test -s /usr/local/bin/show-banner; \
    bash -n /usr/local/bin/show-banner; \
    curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 \
      "https://github.com/infocyph/Toolset/releases/latest/download/install.sh" \
      -o /tmp/toolset-install.sh; \
    test -s /tmp/toolset-install.sh; \
    bash -n /tmp/toolset-install.sh; \
    bash /tmp/toolset-install.sh --prefix /usr/local/bin chromacat; \
    chromacat --version; \
    rm -f /tmp/toolset-install.sh; \
    chmod +x \
      /usr/local/bin/update_httpd.sh \
      /usr/local/bin/entrypoint \
      /usr/local/bin/healthcheck \
      /usr/local/bin/show-banner \
      /usr/local/bin/chromacat; \
    /usr/local/bin/update_httpd.sh; \
    httpd -t; \
    httpd -M > /tmp/httpd.modules; \
    for module in \
      proxy_module \
      proxy_fcgi_module \
      setenvif_module \
      rewrite_module \
      ssl_module \
      socache_shmcb_module \
      headers_module \
      deflate_module \
      http2_module; do \
        grep -Fq " ${module} (shared)" /tmp/httpd.modules || { echo "Required Apache module not loaded: ${module}" >&2; exit 1; }; \
    done; \
    rm -f /tmp/httpd.modules; \
    apk info -e apache2-utils >/dev/null; \
    ! apk info -e apache2 >/dev/null 2>&1; \
    ! apk info -e apache-mod-fcgid >/dev/null 2>&1; \
    command -v ab >/dev/null; \
    command -v htpasswd >/dev/null; \
    { \
        echo '#!/bin/sh'; \
        echo 'case "$-" in *i*) ;; *) return 0 ;; esac'; \
        echo '[ -z "${BANNER_SHOWN-}" ] || return 0'; \
        echo 'command -v show-banner >/dev/null 2>&1 || return 0'; \
        echo 'BANNER_SHOWN=1'; \
        echo 'export BANNER_SHOWN'; \
        echo 'APACHE_VERSION="$(httpd -v | sed -n '\''s|^Server version: Apache/\([0-9.]*\).*|\1|p'\'')"'; \
        echo 'show-banner "Apache ${APACHE_VERSION:-unknown}"'; \
    } > /etc/profile.d/banner-hook.sh; \
    chmod +x /etc/profile.d/banner-hook.sh; \
    printf '\n[ -r /etc/profile.d/banner-hook.sh ] && . /etc/profile.d/banner-hook.sh\n' >> /root/.bashrc

WORKDIR /app

EXPOSE 80 443

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 CMD ["/usr/local/bin/healthcheck"]
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["httpd-foreground"]
