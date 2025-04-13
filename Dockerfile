FROM httpd:alpine
LABEL org.opencontainers.image.source="https://github.com/infocyph/docker-apache"
LABEL org.opencontainers.image.description="Apache"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="infocyph,abmmhasan"
ENV APACHE_LOG_DIR=/var/log/apache2
ENV SERVER_NAME=localhost
RUN apk update && \
    apk add --no-cache apache2-utils apache-mod-fcgid
COPY scripts/update_httpd.sh /usr/local/bin/update_httpd.sh
RUN chmod +x /usr/local/bin/update_httpd.sh && /usr/local/bin/update_httpd.sh
WORKDIR /app
EXPOSE 80 443
CMD ["httpd-foreground"]
