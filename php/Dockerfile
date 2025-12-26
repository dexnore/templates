# syntax=dexnore/dexfile:0

# ========================
# Meta Stage: Global Configuration
# ========================
ARG PHP_VERSION=8.3
ARG ALPINE_VERSION=3.20
ARG BASE_OS=alpine
ARG SERVER_MODE=auto
ARG NODE_VERSION=20
ARG IPE_VERSION=1.6.0

# Auto-detect framework based on files
ARG FRAMEWORK=auto
ARG OPTIMIZE_FOR=production

# ========================
# Stage 0: Framework Detection
# ========================
FROM busybox:latest AS framework-detector

WORKDIR /detect
COPY . .

# Create detection script
RUN cat > /tmp/detect.sh <<'DETECT'
#!/bin/sh
set -e

# Laravel detection
if [ -f "artisan" ] && [ -f "composer.json" ]; then
    grep -q "laravel/framework" composer.json 2>/dev/null && echo "laravel" && exit 0
fi

# Symfony detection
if [ -f "bin/console" ] && [ -f "symfony.lock" ]; then
    echo "symfony" && exit 0
fi

# WordPress detection
if [ -f "wp-config.php" ] || [ -f "wp-config-sample.php" ]; then
    echo "wordpress" && exit 0
fi

# Drupal detection
if [ -f "index.php" ] && [ -d "core" ] && [ -f "core/lib/Drupal.php" ]; then
    echo "drupal" && exit 0
fi

# Magento detection
if [ -f "bin/magento" ] && [ -d "app/etc" ]; then
    echo "magento" && exit 0
fi

# CakePHP detection
if [ -f "bin/cake" ] || ([ -f "composer.json" ] && grep -q "cakephp/cakephp" composer.json 2>/dev/null); then
    echo "cakephp" && exit 0
fi

# CodeIgniter detection
if [ -f "spark" ] || [ -f "system/CodeIgniter.php" ]; then
    echo "codeigniter" && exit 0
fi

# Yii detection
if [ -f "yii" ] && [ -f "composer.json" ] && grep -q "yiisoft/yii2" composer.json 2>/dev/null; then
    echo "yii" && exit 0
fi

# Slim Framework detection
if [ -f "composer.json" ] && grep -q "slim/slim" composer.json 2>/dev/null; then
    echo "slim" && exit 0
fi

# Generic PHP application
if [ -f "composer.json" ] || [ -f "index.php" ]; then
    echo "generic" && exit 0
fi

echo "unknown"
DETECT

RUN chmod +x /tmp/detect.sh && /tmp/detect.sh > /tmp/framework.txt

# ========================
# Stage 1: Base Image Selection
# ========================
FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION} AS base-alpine
FROM php:${PHP_VERSION}-fpm-bookworm AS base-debian

# Choose base based on OS preference
IF RUN [ "${BASE_OS}" = "alpine" ]
    FROM base-alpine AS base
ELSE
    FROM base-debian AS base
ENDIF

# ========================
# Stage 2: System Foundation
# ========================
FROM base AS foundation

ARG TARGETARCH
ARG TARGETPLATFORM
ARG IPE_VERSION
ARG NODE_VERSION

# Copy framework detection result
COPY --from=framework-detector /tmp/framework.txt /tmp/framework.txt

# Environment configuration
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

WORKDIR /app

# Install system dependencies based on OS
IF RUN [ -f /etc/alpine-release ]
    RUN apk add --no-cache \
        bash curl wget git unzip zip tar \
        libzip-dev libpng-dev libjpeg-turbo-dev libwebp-dev freetype-dev \
        libxml2-dev oniguruma-dev icu-dev \
        postgresql-dev sqlite-dev \
        imagemagick-dev bzip2-dev \
        autoconf g++ make linux-headers \
        shadow su-exec tzdata ca-certificates \
        fcgi
ELSE
    RUN apt-get update && apt-get install -y --no-install-recommends \
        bash curl wget git unzip zip tar ca-certificates \
        libzip-dev libpng-dev libjpeg-dev libwebp-dev libfreetype6-dev \
        libxml2-dev libonig-dev libicu-dev \
        libpq-dev libsqlite3-dev \
        libmagickwand-dev libbz2-dev \
        build-essential autoconf pkg-config \
        procps htop net-tools iputils-ping \
        libfcgi-bin \
        && rm -rf /var/lib/apt/lists/*
ENDIF

# Install PHP extension installer
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# Install core PHP extensions
RUN install-php-extensions \
    @composer \
    opcache \
    pdo_mysql \
    pdo_pgsql \
    mysqli \
    pgsql \
    gd \
    zip \
    bz2 \
    intl \
    bcmath \
    soap \
    sockets \
    exif \
    pcntl \
    mbstring \
    xml \
    redis \
    apcu \
    imagick

# Create application user
RUN set -eux; \
    if command -v useradd > /dev/null; then \
        groupadd -r -g 1000 app && \
        useradd -r -u 1000 -g app -m -s /bin/bash app; \
    else \
        addgroup -g 1000 app && \
        adduser -u 1000 -G app -h /home/app -s /bin/bash -D app; \
    fi; \
    mkdir -p /app /var/log/php /run/php; \
    chown -R app:app /app /var/log/php /run/php

# ========================
# Stage 3: Server Installation
# ========================
FROM foundation AS server-installer

ARG SERVER_MODE

# Detect which server to install based on framework and mode
PROC --from=framework-detector cat /tmp/framework.txt
ARG DETECTED_FRAMEWORK="${STDOUT}"

# Install servers based on mode
IF RUN [ "${SERVER_MODE}" = "auto" ] || [ "${SERVER_MODE}" = "nginx" ]
    IF RUN [ -f /etc/alpine-release ]
        RUN apk add --no-cache nginx
    ELSE
        RUN apt-get update && apt-get install -y --no-install-recommends nginx && rm -rf /var/lib/apt/lists/*
    ENDIF
ENDIF

IF RUN [ "${SERVER_MODE}" = "auto" ] || [ "${SERVER_MODE}" = "apache" ]
    IF RUN [ ! -f /etc/alpine-release ]
        RUN apt-get update && apt-get install -y --no-install-recommends apache2 libapache2-mod-fcgid && rm -rf /var/lib/apt/lists/*
        RUN a2dismod mpm_prefork && a2enmod mpm_event proxy_fcgi setenvif rewrite ssl headers http2
    ENDIF
ENDIF

IF RUN [ "${SERVER_MODE}" = "caddy" ]
    RUN if [ "$(uname -m)" = "x86_64" ]; then \
            wget -O /tmp/caddy.tar.gz "https://caddyserver.com/api/download?os=linux&arch=amd64"; \
        else \
            wget -O /tmp/caddy.tar.gz "https://caddyserver.com/api/download?os=linux&arch=arm64"; \
        fi && \
        tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin && \
        chmod +x /usr/local/bin/caddy && \
        rm /tmp/caddy.tar.gz
ENDIF

IF RUN [ "${SERVER_MODE}" = "frankenphp" ]
    RUN FRANKEN_VERSION=$(wget -qO- https://api.github.com/repos/dunglas/frankenphp/releases/latest | grep tag_name | cut -d '"' -f 4) && \
        wget -O /usr/local/bin/frankenphp \
            "https://github.com/dunglas/frankenphp/releases/download/${FRANKEN_VERSION}/frankenphp-linux-$(uname -m)" && \
        chmod +x /usr/local/bin/frankenphp
ENDIF

IF RUN [ "${SERVER_MODE}" = "roadrunner" ] || [ "${SERVER_MODE}" = "octane-rr" ]
    RUN composer global require spiral/roadrunner-cli && \
        ln -s /root/.composer/vendor/bin/rr /usr/local/bin/rr
ENDIF

IF RUN [ "${SERVER_MODE}" = "swoole" ] || [ "${SERVER_MODE}" = "octane-swoole" ] || [ "${DETECTED_FRAMEWORK}" = "laravel" ]
    RUN install-php-extensions swoole
ENDIF

IF RUN [ "${SERVER_MODE}" = "openswoole" ]
    RUN install-php-extensions openswoole
ENDIF

IF RUN [ "${SERVER_MODE}" = "unit" ]
    IF RUN [ ! -f /etc/alpine-release ]
        RUN wget -O /usr/share/keyrings/nginx-keyring.gpg \
                https://unit.nginx.org/keys/nginx-keyring.gpg && \
            echo "deb [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/debian/ bookworm unit" \
                > /etc/apt/sources.list.d/unit.list && \
            apt-get update && apt-get install -y unit unit-php
    ENDIF
ENDIF

# Install Node.js for frontend builds
IF RUN [ -f "package.json" ]
    IF RUN [ -f /etc/alpine-release ]
        RUN apk add --no-cache nodejs npm
    ELSE
        RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
            apt-get install -y nodejs
    ENDIF
    RUN npm install -g npm@latest yarn pnpm
ENDIF

# ========================
# Stage 4: PHP Configuration
# ========================
FROM server-installer AS php-config

# OPcache configuration
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
    echo "opcache.preload_user=app"; \
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
    echo "user = app"; \
    echo "group = app"; \
    echo "listen = 9000"; \
    echo "listen.owner = app"; \
    echo "listen.group = app"; \
    echo "listen.mode = 0660"; \
    echo "pm = dynamic"; \
    echo "pm.max_children = 50"; \
    echo "pm.start_servers = 10"; \
    echo "pm.min_spare_servers = 5"; \
    echo "pm.max_spare_servers = 20"; \
    echo "pm.max_requests = 500"; \
    echo "pm.status_path = /status"; \
    echo "ping.path = /ping"; \
    echo "ping.response = pong"; \
    echo "catch_workers_output = yes"; \
    echo "clear_env = no"; \
    echo "slowlog = /var/log/php/fpm-slow.log"; \
    echo "request_slowlog_timeout = 10s"; \
} > /usr/local/etc/php-fpm.d/zz-docker.conf

# PHP INI configuration
RUN { \
    echo "[PHP]"; \
    echo "memory_limit = \${PHP_MEMORY_LIMIT}"; \
    echo "max_execution_time = \${PHP_MAX_EXECUTION_TIME}"; \
    echo "upload_max_filesize = \${PHP_UPLOAD_MAX_FILESIZE}"; \
    echo "post_max_size = \${PHP_POST_MAX_SIZE}"; \
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
    echo "date.timezone = \${TZ}"; \
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
# Stage 5: Server Configuration
# ========================
FROM php-config AS server-config

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
        echo "        try_files \\\$uri \\\$uri/ /index.php?\\\$query_string;"; \
        echo "    }"; \
        echo ""; \
        echo "    location = /favicon.ico { access_log off; log_not_found off; }"; \
        echo "    location = /robots.txt  { access_log off; log_not_found off; }"; \
        echo ""; \
        echo "    error_page 404 /index.php;"; \
        echo ""; \
        echo "    location ~ \\.php\$ {"; \
        echo "        fastcgi_pass 127.0.0.1:9000;"; \
        echo "        fastcgi_index index.php;"; \
        echo "        fastcgi_param SCRIPT_FILENAME \\\$realpath_root\\\$fastcgi_script_name;"; \
        echo "        include fastcgi_params;"; \
        echo "        fastcgi_buffers 16 16k;"; \
        echo "        fastcgi_buffer_size 32k;"; \
        echo "    }"; \
        echo ""; \
        echo "    location ~ /\\.(?!well-known).* {"; \
        echo "        deny all;"; \
        echo "    }"; \
        echo "}"; \
    } > /etc/nginx/sites-available/default && \
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default || true

# Apache configuration
IF RUN [ -f /etc/apache2/apache2.conf ]
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
        echo "    <FilesMatch \\.php\$>"; \
        echo "        SetHandler 'proxy:fcgi://127.0.0.1:9000'"; \
        echo "    </FilesMatch>"; \
        echo ""; \
        echo "    ErrorLog \\\${APACHE_LOG_DIR}/error.log"; \
        echo "    CustomLog \\\${APACHE_LOG_DIR}/access.log combined"; \
        echo "</VirtualHost>"; \
    } > /etc/apache2/sites-available/000-default.conf
ENDIF

# Caddy configuration
RUN mkdir -p /etc/caddy && \
    { \
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

# ========================
# Stage 6: Dependency Installation
# ========================
FROM server-config AS dependencies

WORKDIR /app

# Copy dependency manifests first (for caching)
COPY --chown=app:app composer.json composer.lock* ./

# Install PHP dependencies
RUN --mount=type=cache,target=/root/.composer \
    composer install \
        --no-dev \
        --no-scripts \
        --no-autoloader \
        --prefer-dist \
        --no-interaction \
        --optimize-autoloader

# Install Node dependencies if package.json exists
IF RUN [ -f "package.json" ]
    COPY --chown=app:app package.json package-lock.json* yarn.lock* pnpm-lock.yaml* bun.lockb* .npmrc* .yarnrc* ./
    
    RUN if [ -f "pnpm-lock.yaml" ]; then \
            pnpm install --prod --frozen-lockfile; \
        elif [ -f "yarn.lock" ]; then \
            yarn install --production --frozen-lockfile; \
        elif [ -f "package-lock.json" ]; then \
            npm ci --production; \
        elif [ -f "package.json" ]; then \
            npm install --production; \
        fi
ENDIF

# ========================
# Stage 7: Application Build
# ========================
FROM dependencies AS builder

# Copy application code
COPY --chown=app:app . .

# Generate optimized autoloader
RUN composer dump-autoload \
    --optimize \
    --no-dev \
    --classmap-authoritative

# Build frontend assets if needed
IF RUN [ -f "vite.config.js" ] || [ -f "vite.config.ts" ] || [ -f "webpack.mix.js" ] || [ -f "webpack.config.js" ]
    RUN if [ -f "vite.config.js" ] || [ -f "vite.config.ts" ]; then \
            npm run build || yarn build || pnpm build || true; \
        elif [ -f "webpack.mix.js" ]; then \
            npm run production || yarn production || true; \
        elif [ -f "webpack.config.js" ]; then \
            npm run build:prod || yarn build:prod || true; \
        fi
ENDIF

# Framework-specific optimizations
PROC cat /tmp/framework.txt
ARG DETECTED_FRAMEWORK="${STDOUT}"

IF RUN [ "${DETECTED_FRAMEWORK}" = "laravel" ] && [ -f "artisan" ]
    RUN php artisan config:cache && \
        php artisan route:cache && \
        php artisan view:cache && \
        php artisan event:cache || true
ENDIF

IF RUN [ "${DETECTED_FRAMEWORK}" = "symfony" ] && [ -f "bin/console" ]
    RUN php bin/console cache:clear --env=prod --no-debug && \
        php bin/console cache:warmup --env=prod --no-debug || true
ENDIF

# Set correct permissions
RUN find /app -type f -exec chmod 644 {} \; && \
    find /app -type d -exec chmod 755 {} \; && \
    if [ -f "artisan" ]; then chmod +x artisan; fi && \
    if [ -f "bin/console" ]; then chmod +x bin/console; fi

# ========================
# Stage 8: Universal Entrypoint
# ========================
FROM builder AS runtime

# Create intelligent entrypoint
RUN cat > /usr/local/bin/docker-entrypoint.sh <<'ENTRYPOINT'
#!/usr/bin/env bash
set -euo pipefail

# Read detected framework
FRAMEWORK=$(cat /tmp/framework.txt 2>/dev/null || echo "generic")

# Environment variables
SERVER_MODE="${SERVER_MODE:-auto}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
PHP_FPM_PORT="${PHP_FPM_PORT:-9000}"
WORKERS="${WORKERS:-$(nproc)}"

echo "🔍 Detected framework: $FRAMEWORK"
echo "🚀 Server mode: $SERVER_MODE"

# Handle CLI commands
if [ "$#" -gt 0 ]; then
    case "$1" in
        artisan|bin/console|wp|drush|composer|php)
            exec "$@"
            ;;
        bash|sh|/bin/bash|/bin/sh)
            exec "$@"
            ;;
    esac
fi

# Auto-detect best server mode based on framework
if [ "$SERVER_MODE" = "auto" ]; then
    case "$FRAMEWORK" in
        laravel)
            if command -v rr > /dev/null && [ -f "artisan" ]; then
                SERVER_MODE="octane-rr"
            elif php -m | grep -q swoole && [ -f "artisan" ]; then
                SERVER_MODE="octane-swoole"
            else
                SERVER_MODE="php-fpm"
            fi
            ;;
        symfony)
            if command -v frankenphp > /dev/null; then
                SERVER_MODE="frankenphp"
            else
                SERVER_MODE="php-fpm"
            fi
            ;;
        wordpress|drupal)
            SERVER_MODE="php-fpm"
            ;;
        *)
            SERVER_MODE="php-fpm"
            ;;
    esac
fi

echo "✅ Using server mode: $SERVER_MODE"

# Determine document root
DOC_ROOT="/app/public"
if [ ! -d "/app/public" ]; then
    DOC_ROOT="/app"
fi

# Start appropriate server
case "$SERVER_MODE" in
    php-fpm)
        echo "▶️ Starting PHP-FPM on port $PHP_FPM_PORT"
        exec php-fpm -F
        ;;
    
    octane-swoole)
        echo "▶️ Starting Laravel Octane (Swoole) on port $PORT"
        exec php artisan octane:start \
            --server=swoole \
            --host="$HOST" \
            --port="$PORT" \
            --workers="$WORKERS"
        ;;
    
    octane-rr)
        echo "▶️ Starting Laravel Octane (RoadRunner) on port $PORT"
        exec php artisan octane:start \
            --server=roadrunner \
            --host="$HOST" \
            --port="$PORT" \
            --rpc-port=6001 \
            --workers="$WORKERS"
        ;;
    
    frankenphp)
        echo "▶️ Starting FrankenPHP on port $PORT"
        cd "$DOC_ROOT" 2>/dev/null || cd /app
        exec frankenphp php-server --listen "$HOST:$PORT"
        ;;
    
    roadrunner|rr)
        echo "▶️ Starting RoadRunner on port $PORT"
        exec rr serve -c /app/.rr.yaml
        ;;
    
    swoole)
        echo "▶️ Starting Swoole on port $PORT"
        if [ -f "/app/swoole.php" ]; then
            exec php /app/swoole.php
        else
            echo "❌ swoole.php not found"
            exit 1
        fi
        ;;
    
    caddy)
        echo "▶️ Starting Caddy + PHP-FPM"
        php-fpm -D
        exec caddy run --config /etc/caddy/Caddyfile
        ;;
    
    nginx)
        echo "▶️ Starting Nginx + PHP-FPM"
        php-fpm -D
        exec nginx -g "daemon off;"
        ;;
    
    dev)
        echo "▶️ Starting PHP built-in server (DEV ONLY)"
        cd "$DOC_ROOT"
        exec php -S "$HOST:$PORT"
        ;;
    
    *)
        echo "❌ Unknown SERVER_MODE: $SERVER_MODE"
        exit 1
        ;;
esac
ENTRYPOINT

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Health check script
RUN cat > /usr/local/bin/healthcheck.sh <<'HEALTHCHECK'
#!/usr/bin/env bash
set -e

SERVER_MODE="${SERVER_MODE:-php-fpm}"
PORT="${PORT:-8080}"
PHP_FPM_PORT="${PHP_FPM_PORT:-9000}"

case "$SERVER_MODE" in
    php-fpm|auto)
        if command -v cgi-fcgi > /dev/null; then
            SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET \
                cgi-fcgi -bind -connect 127.0.0.1:$PHP_FPM_PORT || exit 1
        else
            wget -qO- http://localhost:$PHP_FPM_PORT/ping || exit 1
        fi
        ;;
    *)
        wget -qO- http://localhost:$PORT/ || curl -f http://localhost:$PORT/ || exit 1
        ;;
esac
HEALTHCHECK

RUN chmod +x /usr/local/bin/healthcheck.sh

# ========================
# Stage 9: Production Release
# ========================
FROM runtime AS production

WORKDIR /app

# Remove development tools
IF RUN [ ! -f /etc/alpine-release ]
    RUN apt-get purge -y build-essential autoconf pkg-config && \
        apt-get autoremove -y && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*
ENDIF

# Security hardening
RUN rm -rf /tmp/* /var/tmp/* && \
    find /app -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# Framework-specific permissions
PROC cat /tmp/framework.txt
ARG DETECTED_FRAMEWORK="${STDOUT}"

IF RUN [ "${DETECTED_FRAMEWORK}" = "laravel" ]
    RUN mkdir -p storage/framework/{sessions,views,cache} storage/logs bootstrap/cache && \
        chown -R app:app storage bootstrap/cache && \
        chmod -R 775 storage bootstrap/cache
ENDIF

IF RUN [ "${DETECTED_FRAMEWORK}" = "symfony" ]
    RUN mkdir -p var/cache var/log && \
        chown -R app:app var && \
        chmod -R 775 var
ENDIF

IF RUN [ "${DETECTED_FRAMEWORK}" = "wordpress" ]
    RUN mkdir -p wp-content/uploads && \
        chown -R app:app wp-content && \
        chmod -R 775 wp-content
ENDIF

USER app

EXPOSE 8080 9000

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

STOPSIGNAL SIGQUIT

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []

# ========================
# Metadata
# ========================
LABEL org.opencontainers.image.title="Universal PHP Application" \
      org.opencontainers.image.description="Auto-detecting PHP framework container" \
      org.opencontainers.image.vendor="Dexnore" \
      com.dexnore.auto-detect="true" \
      com.dexnore.supports="laravel,symfony,wordpress,drupal,generic"