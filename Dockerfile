FROM httpd:alpine
LABEL org.opencontainers.image.source="https://github.com/infocyph/docker-apache"
LABEL org.opencontainers.image.description="Apache"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="infocyph,abmmhasan"
ENV APACHE_LOG_DIR=/var/log/apache2
ENV SERVER_NAME=localhost
RUN apk update && \
    apk add --no-cache apache2-utils apache-mod-fcgid tzdata bash figlet ncurses musl-locales gawk && \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/* \
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8
COPY --chmod=+x scripts/update_httpd.sh /usr/local/bin/update_httpd.sh
ADD --chmod=+x https://raw.githubusercontent.com/infocyph/Scriptomatic/master/bash/banner.sh /usr/local/bin/show-banner
ADD --chmod=+x https://raw.githubusercontent.com/infocyph/Toolset/main/ChromaCat/chromacat /usr/local/bin/chromacat
RUN /usr/local/bin/update_httpd.sh && \
    APACHE_VERSION=$(httpd -v | sed -n 's|^Server version: Apache/\([0-9\.]*\).*|\1|p') && \
    echo "show-banner \"APACHE $APACHE_VERSION\"" >> /root/.bashrc
WORKDIR /app
EXPOSE 80 443
CMD ["httpd-foreground"]
