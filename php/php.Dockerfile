# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

# ========================
# Stage 1: Base image & tools
# ========================
FROM php:8.2-fpm AS base

ARG PHP_EXTENSIONS="pdo pdo_mysql pdo_pgsql pgsql mysqli zip bz2 gd intl bcmath soap sockets exif pcntl opcache redis apcu imagick mbstring xml curl json fileinfo tokenizer iconv simplexml dom xmlwriter xmlreader"
ARG PECL_EXTENSIONS="redis apcu imagick"

ENV HOME=/root \
    DEBIAN_FRONTEND=noninteractive \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/root/.composer \
    PATH=/root/.composer/vendor/bin:/usr/local/bin:/opt/bin:$PATH \
    PHP_MEMORY_LIMIT=512M \
    PHP_MAX_EXECUTION_TIME=300 \
    PHP_UPLOAD_MAX_FILESIZE=128M \
    PHP_POST_MAX_SIZE=128M \
    TZ=UTC \
    APP_ENV=production \
    APP_DEBUG=false
    PHP_SERVE_MODE=PRODUCTION \
    APP_PORT=9000

WORKDIR /home/dexfile/app

# Detect OS and install dependencies
RUN if [ -f /etc/alpine-release ]; then \
        apk add --no-cache \
            bash curl wget git unzip zip tar \
            libzip-dev libpng-dev libjpeg-turbo-dev libwebp-dev freetype-dev \
            libxml2-dev oniguruma-dev icu-dev \
            postgresql-dev sqlite-dev \
            imagemagick-dev bzip2-dev \
            autoconf g++ make linux-headers \
            shadow su-exec tzdata ca-certificates \
            nginx apache2 apache2-utils \
            fcgi; \
    else \
        apt-get update && apt-get install -y --no-install-recommends \
            bash curl wget git unzip zip tar ca-certificates \
            libzip-dev libpng-dev libjpeg-dev libwebp-dev libfreetype6-dev \
            libxml2-dev libonig-dev libicu-dev \
            libpq-dev libsqlite3-dev \
            libmagickwand-dev libbz2-dev \
            build-essential autoconf pkg-config \
            procps htop net-tools iputils-ping \
            nginx apache2 libapache2-mod-fcgid \
            supervisor cron \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# Install docker-php-extension-installer for easier extension management
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# Install PHP extensions
RUN set -eux; \
    install-php-extensions \
        @composer \
        pdo_mysql pdo_pgsql mysqli pgsql \
        gd zip bz2 intl bcmath soap sockets \
        exif pcntl opcache mbstring xml \
        redis apcu imagick

# Create application user and directories
RUN set -eux; \
    if command -v useradd > /dev/null; then \
        groupadd -r -g 1000 appuser && \
        useradd -r -u 1000 -g appuser -m -s /bin/bash appuser; \
    else \
        addgroup -g 1000 appuser && \
        adduser -u 1000 -G appuser -h /home/appuser -s /bin/bash -D appuser; \
    fi; \
    mkdir -p /app /var/www/html /var/log/php /var/log/supervisor \
             /run/php /var/cache/nginx /var/cache/apache2 \
             /etc/caddy /etc/unit /var/lib/unit; \
    chown -R appuser:appuser /app /var/www/html /var/log/php /run/php

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- \
        --install-dir=/usr/local/bin \
        --filename=composer \
        --version=latest


# ========================
# Stage 3: PHP Configuration
# ========================
FROM base AS php-config

# OPcache configuration (production optimized)
RUN { \
        echo "[opcache]"; \
        echo "opcache.enable=1"; \
        echo "opcache.enable_cli=0"; \
        echo "opcache.memory_consumption=256"; \
        echo "opcache.interned_strings_buffer=16"; \
        echo "opcache.max_accelerated_files=20000"; \
        echo "opcache.validate_timestamps=0"; \
        echo "opcache.revalidate_freq=0"; \
        echo "opcache.save_comments=1"; \
        echo "opcache.fast_shutdown=1"; \
        echo "opcache.file_cache=/var/cache/opcache"; \
        echo "opcache.file_cache_only=0"; \
        echo "opcache.huge_code_pages=1"; \
        echo "opcache.preload_user=appuser"; \
    } > /usr/local/etc/php/conf.d/10-opcache.ini

# PHP-FPM configuration
RUN { \
        echo "[global]"; \
        echo "error_log = /var/log/php/fpm-error.log"; \
        echo "log_level = warning"; \
        echo "emergency_restart_threshold = 10"; \
        echo "emergency_restart_interval = 1m"; \
        echo "process_control_timeout = 10s"; \
        echo "daemonize = no"; \
        echo ""; \
        echo "[www]"; \
        echo "user = appuser"; \
        echo "group = appuser"; \
        echo "listen = 9000"; \
        echo "listen.owner = appuser"; \
        echo "listen.group = appuser"; \
        echo "listen.mode = 0660"; \
        echo "pm = dynamic"; \
        echo "pm.max_children = 50"; \
        echo "pm.start_servers = 10"; \
        echo "pm.min_spare_servers = 5"; \
        echo "pm.max_spare_servers = 20"; \
        echo "pm.max_requests = 500"; \
        echo "pm.status_path = /php-fpm-status"; \
        echo "ping.path = /php-fpm-ping"; \
        echo "ping.response = pong"; \
        echo "catch_workers_output = yes"; \
        echo "decorate_workers_output = no"; \
        echo "clear_env = no"; \
        echo "slowlog = /var/log/php/fpm-slow.log"; \
        echo "request_slowlog_timeout = 10s"; \
    } > /usr/local/etc/php-fpm.d/zz-docker.conf

# PHP INI configuration
RUN { \
        echo "[PHP]"; \
        echo "memory_limit = ${PHP_MEMORY_LIMIT}"; \
        echo "max_execution_time = ${PHP_MAX_EXECUTION_TIME}"; \
        echo "upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}"; \
        echo "post_max_size = ${PHP_POST_MAX_SIZE}"; \
        echo "max_input_vars = 5000"; \
        echo "max_input_time = 300"; \
        echo "default_socket_timeout = 60"; \
        echo ""; \
        echo "expose_php = Off"; \
        echo "display_errors = Off"; \
        echo "display_startup_errors = Off"; \
        echo "log_errors = On"; \
        echo "error_log = /var/log/php/error.log"; \
        echo "error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT"; \
        echo ""; \
        echo "date.timezone = ${TZ}"; \
        echo ""; \
        echo "realpath_cache_size = 4096K"; \
        echo "realpath_cache_ttl = 600"; \
        echo ""; \
        echo "session.save_handler = files"; \
        echo "session.save_path = /tmp"; \
        echo "session.use_strict_mode = 1"; \
        echo "session.cookie_httponly = 1"; \
        echo "session.cookie_samesite = Lax"; \
        echo "session.cookie_secure = 1"; \
    } > /usr/local/etc/php/conf.d/99-production.ini

# ========================
# Stage 4: Server Configurations
# ========================
FROM php-config AS server-configs

# Nginx configuration
RUN mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled && \
    { \
        echo "server {"; \
        echo "    listen 80 default_server;"; \
        echo "    listen [::]:80 default_server;"; \
        echo "    server_name _;"; \
        echo "    root /app/public;"; \
        echo "    index index.php index.html;"; \
        echo "    charset utf-8;"; \
        echo ""; \
        echo "    location / {"; \
        echo "        try_files \$uri \$uri/ /index.php?\$query_string;"; \
        echo "    }"; \
        echo ""; \
        echo "    location = /favicon.ico { access_log off; log_not_found off; }"; \
        echo "    location = /robots.txt  { access_log off; log_not_found off; }"; \
        echo ""; \
        echo "    error_page 404 /index.php;"; \
        echo ""; \
        echo "    location ~ \.php$ {"; \
        echo "        fastcgi_pass 127.0.0.1:9000;"; \
        echo "        fastcgi_index index.php;"; \
        echo "        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;"; \
        echo "        include fastcgi_params;"; \
        echo "        fastcgi_buffers 16 16k;"; \
        echo "        fastcgi_buffer_size 32k;"; \
        echo "    }"; \
        echo ""; \
        echo "    location ~ /\.(?!well-known).* {"; \
        echo "        deny all;"; \
        echo "    }"; \
        echo "}"; \
    } > /etc/nginx/sites-available/default && \
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Apache configuration
RUN { \
        echo "<VirtualHost *:80>"; \
        echo "    ServerAdmin webmaster@localhost"; \
        echo "    DocumentRoot /app/public"; \
        echo ""; \
        echo "    <Directory /app/public>"; \
        echo "        Options -Indexes +FollowSymLinks"; \
        echo "        AllowOverride All"; \
        echo "        Require all granted"; \
        echo "    </Directory>"; \
        echo ""; \
        echo "    <FilesMatch \.php$>"; \
        echo "        SetHandler 'proxy:fcgi://127.0.0.1:9000'"; \
        echo "    </FilesMatch>"; \
        echo ""; \
        echo "    ErrorLog \${APACHE_LOG_DIR}/error.log"; \
        echo "    CustomLog \${APACHE_LOG_DIR}/access.log combined"; \
        echo "</VirtualHost>"; \
    } > /etc/apache2/sites-available/000-default.conf

# Caddy configuration
RUN { \
        echo "{"; \
        echo "    auto_https off"; \
        echo "    admin off"; \
        echo "}"; \
        echo ""; \
        echo ":80 {"; \
        echo "    root * /app/public"; \
        echo "    php_fastcgi 127.0.0.1:9000"; \
        echo "    file_server"; \
        echo "    encode gzip"; \
        echo ""; \
        echo "    log {"; \
        echo "        output stdout"; \
        echo "        format console"; \
        echo "    }"; \
        echo "}"; \
    } > /etc/caddy/Caddyfile

# RoadRunner configuration
RUN { \
        echo "version: '3'"; \
        echo ""; \
        echo "server:"; \
        echo "  command: 'php worker.php'"; \
        echo "  relay: 'pipes'"; \
        echo ""; \
        echo "http:"; \
        echo "  address: '0.0.0.0:8080'"; \
        echo "  max_request_size: 128"; \
        echo "  pool:"; \
        echo "    num_workers: 4"; \
        echo "    max_jobs: 100"; \
        echo "    allocate_timeout: 60s"; \
        echo "    destroy_timeout: 60s"; \
        echo ""; \
        echo "logs:"; \
        echo "  mode: production"; \
        echo "  level: warn"; \
    } > /app/.rr.yaml

# Nginx Unit configuration
RUN { \
        echo "{"; \
        echo "    \"listeners\": {"; \
        echo "        \"*:8080\": {"; \
        echo "            \"pass\": \"applications/app\""; \
        echo "        }"; \
        echo "    },"; \
        echo "    \"applications\": {"; \
        echo "        \"app\": {"; \
        echo "            \"type\": \"php\","; \
        echo "            \"root\": \"/app/public\","; \
        echo "            \"index\": \"index.php\","; \
        echo "            \"script\": \"index.php\""; \
        echo "        }"; \
        echo "    }"; \
        echo "}"; \
    } > /etc/unit/config.json

# Supervisor configuration for multi-process management
RUN mkdir -p /etc/supervisor/conf.d && \
    { \
        echo "[supervisord]"; \
        echo "nodaemon=true"; \
        echo "user=root"; \
        echo "logfile=/var/log/supervisor/supervisord.log"; \
        echo "pidfile=/var/run/supervisord.pid"; \
        echo ""; \
        echo "[program:php-fpm]"; \
        echo "command=php-fpm -F"; \
        echo "autostart=true"; \
        echo "autorestart=true"; \
        echo "stdout_logfile=/dev/stdout"; \
        echo "stdout_logfile_maxbytes=0"; \
        echo "stderr_logfile=/dev/stderr"; \
        echo "stderr_logfile_maxbytes=0"; \
    } > /etc/supervisor/supervisord.conf


# ========================
# Stage 2: Dependency caching
# ========================
FROM base AS deps

WORKDIR /home/dexfile/app
COPY composer.json composer.lock* ./
RUN composer install --no-autoloader --no-scripts --no-progress --prefer-dist

# ========================
# Stage 3: Runtime image
# ========================
FROM base AS runtime

WORKDIR /home/dexfile/app

# Copy dependencies and source code
COPY --from=deps /home/dexfile/app/vendor ./vendor
COPY --from=deps /home/dexfile/app/composer.* ./
COPY . .

# Optimize autoloader
RUN composer dump-autoload --optimize --no-dev --classmap-authoritative

# Set ownership and permissions
RUN chown -R dexfile:dexnore /home/dexfile/app \
    && find /home/dexfile/app -type d -exec chmod 755 {} \; \
    && find /home/dexfile/app -type f -exec chmod 644 {} \; \
    && mkdir -p /var/cache/php-opcache /var/log/php-fpm \
    && chown -R dexfile:dexnore /var/cache/php-opcache /var/log/php-fpm

# PHP INI: OPcache & memory
RUN { \
        echo "opcache.enable=1"; \
        echo "opcache.enable_cli=0"; \
        echo "opcache.memory_consumption=256"; \
        echo "opcache.max_accelerated_files=10000"; \
        echo "opcache.validate_timestamps=0"; \
        echo "opcache.revalidate_freq=0"; \
        echo "opcache.file_cache=/var/cache/php-opcache"; \
      } > /usr/local/etc/php/conf.d/opcache.ini

RUN { \
        echo "memory_limit=512M"; \
        echo "error_reporting=E_ALL & ~E_DEPRECATED & ~E_STRICT"; \
        echo "display_errors=0"; \
        echo "log_errors=1"; \
        echo "error_log=/var/log/php-fpm/error.log"; \
      } > /usr/local/etc/php/conf.d/docker-php-custom.ini

# ------------------------
# Intelligent Entrypoint
# ------------------------
RUN mkdir -p /usr/local/bin && \
  cat <<'EOF' /usr/local/bin/entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail

MODE="${PHP_SERVE_MODE:-PRODUCTION}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-${APP_PORT:-9000}}"
APP_DIR="/home/dexfile/app"
FRAMEWORK_CLI=("artisan" "bin/console")

if [ "$#" -gt 0 ]; then
    for cli in "${FRAMEWORK_CLI[@]}"; do
        if [[ "$1" == "$cli" ]]; then
            echo "Running framework CLI command: php $*"
            exec php "$@"
        fi
    done
    echo "Running custom command: $*"
    exec "$@"
fi

case "$MODE" in
  "STANDALONE_DEV")
    if [ -f "$APP_DIR/public/index.php" ]; then
      echo "Starting PHP built-in server (dev) on ${HOST}:${PORT} (public/)"
      exec php -S "${HOST}:${PORT}" -t public
    elif [ -f "$APP_DIR/index.php" ]; then
      echo "Starting PHP built-in server (dev) on ${HOST}:${PORT} (root/)"
      exec php -S "${HOST}:${PORT}" -t .
    else
      echo >&2 "FATAL: No index.php found for dev server."
      exit 1
    fi
    ;;
  "STANDALONE_PROD")
    echo "Starting PHP-FPM production server"
    exec php-fpm
    ;;
  "SWS")
    if [ -x /usr/local/bin/swoole-server.sh ]; then
      echo "Starting Swoole server"
      exec /usr/local/bin/swoole-server.sh
    else
      echo >&2 "FATAL: Swoole server script missing."
      exit 1
    fi
    ;;
  "RR")
    if [ -x /usr/local/bin/roadrunner-server.sh ]; then
      echo "Starting RoadRunner server"
      exec /usr/local/bin/roadrunner-server.sh
    else
      echo >&2 "FATAL: RoadRunner server script missing."
      exit 1
    fi
    ;;
  *)
    echo "Starting PHP-FPM (default)"
    exec php-fpm
    ;;
esac
EOF

RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm"]

# ========================
# Stage 4: Builder
# ========================
FROM runtime AS builder

WORKDIR /home/dexfile/app

RUN if [ -f artisan ]; then php artisan config:cache; fi; \
    if [ -f bin/console ]; then php bin/console cache:clear; fi

# ========================
# Stage 5: Production image
# ========================
FROM runtime AS prod

COPY --from=builder --chown=dexfile:dexnore /home/dexfile/app /home/dexfile/app

RUN mkdir -p /home/dexfile/app/storage/logs /var/cache/php-opcache /var/log/php-fpm \
    && chown -R dexfile:dexnore /home/dexfile/app/storage /var/cache/php-opcache /var/log/php-fpm

USER root
RUN CPU_CORES=$(nproc) && \
    MAX_CHILDREN=$((CPU_CORES * 5)) && \
    START_SERVERS=$((CPU_CORES * 2)) && \
    MIN_SPARE=$CPU_CORES && \
    MAX_SPARE=$((CPU_CORES * 3)) && \
    cat > /usr/local/etc/php-fpm.d/www.conf <<EOF
[www]
user = dexfile
group = dexnore
listen = ${APP_PORT:-9000}
pm = dynamic
pm.max_children = $MAX_CHILDREN
pm.start_servers = $START_SERVERS
pm.min_spare_servers = $MIN_SPARE
pm.max_spare_servers = $MAX_SPARE
pm.max_requests = 500
catch_workers_output = yes
slowlog = /var/log/php-fpm/slow.log
EOF
USER dexnore:dexfile

CMD ["php-fpm"]

# ========================
# Stage 6: Release
# ========================
FROM prod AS release
EXPOSE ${APP_PORT:-9000}
LABEL maintainer="@dexnore/dexfile"

# ========================
# Stage 7: Optional Swoole
# ========================
FROM prod AS swoole

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        libssl-dev pkg-config \
    && pecl install swoole \
    && docker-php-ext-enable swoole \
    && rm -rf /var/lib/apt/lists/*

USER dexnore:dexfile
RUN mkdir -p /usr/local/bin && \
    cat <<'EOF' > /usr/local/bin/swoole-server.sh
#!/usr/bin/env bash
set -e
echo "Starting Swoole HTTP server..."
exec php -d memory_limit=512M /home/dexfile/app/swoole-http-server.php
EOF

RUN chmod +x /usr/local/bin/swoole-server.sh

# ========================
# Stage 8: Optional RoadRunner
# ========================
FROM prod AS roadrunner

USER root
RUN apt-get update && apt-get install -y --no-install-recommends unzip curl git \
    && rm -rf /var/lib/apt/lists/*

RUN composer global require spiral/roadrunner \
    && ln -s /root/.composer/vendor/bin/rr /usr/local/bin/rr

USER dexnore:dexfile
RUN mkdir -p /usr/local/bin && \
    cat <<'EOF' > /usr/local/bin/roadrunner-server.sh
#!/usr/bin/env bash
set -e
HOST=${HOST:-0.0.0.0}
PORT=${PORT:-8080}
WORKERS=${RR_NUM_WORKERS:-$(nproc)}

if [ ! -f .rr.yaml ]; then
    echo "Creating default .rr.yaml config..."
    cat > .rr.yaml <<EOC
version: "2.7"
server:
  command: "php worker.php"
http:
  address: "${HOST}:${PORT}"
  workers:
    pool:
      num_workers: $WORKERS
EOC
fi

echo "Starting RoadRunner HTTP server on ${HOST}:${PORT}..."
exec rr serve
EOF
RUN chmod +x /usr/local/bin/roadrunner-server.sh
ENTRYPOINT ["/usr/local/bin/python-entrypoint.py"]

# ========================
# Stage 6: Release image
# ========================
FROM prod AS release
EXPOSE ${PORT:-3000}
LABEL maintainer="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"
