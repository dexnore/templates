# syntax=docker/dockerfile:1.7

ARG IPE_VERSION=1.6.0
###############################################################################
# PHP runtime base (single-image nginx + php-fpm)
###############################################################################
FROM php:8.3-fpm-alpine AS php-runtime-base
ARG IPE_VERSION=$IPE_VERSION
RUN set -eux; \
    apk add --no-cache \
        ca-certificates \
        tzdata \
        nginx \
        supervisor; \
    \
    apk add --no-cache --virtual .build-tools curl; \
    curl -fsSL \
      https://github.com/mlocati/docker-php-extension-installer/releases/download/${IPE_VERSION}/install-php-extensions \
      -o /usr/local/bin/install-php-extensions; \
    chmod +x /usr/local/bin/install-php-extensions; \
    \
    install-php-extensions \
        opcache \
        bcmath \
        exif \
        intl \
        gd \
        zip \
        pdo_mysql \
        pdo_pgsql \
        redis \
        pcntl; \
    \
    rm /usr/local/bin/install-php-extensions; \
    apk del .build-tools

###############################################################################
# PHP configuration
###############################################################################
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY <<'EOF' $PHP_INI_DIR/conf.d/zz-production.ini
expose_php=0
memory_limit=512M
max_execution_time=60
upload_max_filesize=50M
post_max_size=50M

realpath_cache_size=4096K
realpath_cache_ttl=600

opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0
EOF

COPY <<'EOF' /usr/local/etc/php-fpm.d/zz-fpm.conf
[global]
daemonize = no

[www]
user = app
group = app
listen = 127.0.0.1:9000

pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8
pm.max_requests = 500

clear_env = no
catch_workers_output = yes

php_admin_flag[log_errors] = on
php_admin_value[error_log] = /dev/stderr
EOF

###############################################################################
# Builder (Composer with BuildKit cache)
###############################################################################
FROM php-runtime-base AS builder

WORKDIR /app
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock ./

RUN --mount=type=cache,target=/tmp/cache/composer \
    COMPOSER_CACHE_DIR=/tmp/cache/composer \
    composer validate --no-check-publish && \
    composer install \
      --no-dev \
      --no-scripts \
      --no-autoloader \
      --prefer-dist \
      --no-interaction \
      --no-progress

COPY . .
RUN composer dump-autoload --optimize --classmap-authoritative

###############################################################################
# Final runtime
###############################################################################
FROM php-runtime-base AS final

RUN set -eux; \
    addgroup -S app && adduser -S -G app app; \
    mkdir -p \
      /var/www/html \
      /run/nginx \
      /var/lib/nginx \
      /var/log/nginx \
      /tmp/client_temp \
      /tmp/proxy_temp_path \
      /tmp/fastcgi_temp; \
    chown -R app:app \
      /var/www/html \
      /run/nginx \
      /var/lib/nginx \
      /var/log/nginx \
      /tmp

###############################################################################
# Nginx configuration (non-root, read-only FS compatible)
###############################################################################
COPY <<'EOF' /etc/nginx/nginx.conf
user app;
worker_processes auto;
pid /tmp/nginx.pid;

events {
    worker_connections 2048;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    client_body_temp_path /tmp/client_temp;
    proxy_temp_path       /tmp/proxy_temp_path;
    fastcgi_temp_path     /tmp/fastcgi_temp;

    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    client_max_body_size 50M;

    access_log /dev/stdout;
    error_log /dev/stderr warn;

    include /etc/nginx/conf.d/*.conf;
}
EOF

COPY <<'EOF' /etc/nginx/conf.d/default.conf
server {
    listen 8080;
    server_name _;
    root /var/www/html/public;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_read_timeout 300;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

###############################################################################
# Supervisor (graceful shutdown, correct logging)
###############################################################################
COPY <<'EOF' /etc/supervisord.conf
[supervisord]
nodaemon=true
pidfile=/tmp/supervisord.pid

[program:php-fpm]
command=php-fpm -F
priority=10
stopsignal=QUIT
stopwaitsecs=20
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:nginx]
command=nginx -g "daemon off;"
priority=20
stopsignal=QUIT
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

###############################################################################
# Application
###############################################################################
WORKDIR /var/www/html
COPY --from=builder --chown=app:app /app /var/www/html

USER app
EXPOSE 8080
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/ || exit 1

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
