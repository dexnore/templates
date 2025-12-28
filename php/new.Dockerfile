# syntax=docker/dockerfile:1.4
# Dexfile: Universal PHP Production Container
# Supports: PHP-FPM, Apache, Nginx, Caddy, FrankenPHP, RoadRunner, Swoole, Unit
# Frameworks: Laravel, Symfony, WordPress, Drupal, and more

# ========================
# Global Build Arguments
# ========================
ARG PHP_VERSION=8.3
ARG ALPINE_VERSION=3.19
ARG DEBIAN_VERSION=bookworm
ARG BASE_OS=debian
ARG NODE_VERSION=20

# ========================
# Stage 0: Base Image Selector
# ========================
FROM php:${PHP_VERSION}-fpm-${DEBIAN_VERSION} AS base-debian
FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION} AS base-alpine
FROM base-${BASE_OS} AS base

# ========================
# Stage 1: System Foundation
# ========================
FROM base AS foundation

ARG TARGETARCH
ARG TARGETPLATFORM
ARG PHP_EXTENSIONS="pdo pdo_mysql pdo_pgsql pgsql mysqli zip bz2 gd intl bcmath soap sockets exif pcntl opcache redis apcu imagick mbstring xml curl json fileinfo tokenizer iconv simplexml dom xmlwriter xmlreader"
ARG PECL_EXTENSIONS="redis apcu imagick"

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

# Install Node.js and package managers (for frontend builds)
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs || apk add --no-cache nodejs npm; \
    npm install -g npm@latest yarn pnpm bun

# ========================
# Stage 2: Web Server Installers
# ========================
FROM foundation AS webservers

# Install Caddy
RUN curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && \
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list && \
    apt-get update && apt-get install -y caddy || \
    (wget -O /tmp/caddy.tar.gz "https://caddyserver.com/api/download?os=linux&arch=${TARGETARCH}" && \
     tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin && \
     chmod +x /usr/local/bin/caddy && \
     rm /tmp/caddy.tar.gz)

# Install FrankenPHP
RUN FRANKEN_VERSION=$(curl -s https://api.github.com/repos/dunglas/frankenphp/releases/latest | grep tag_name | cut -d '"' -f 4) && \
    curl -L "https://github.com/dunglas/frankenphp/releases/download/${FRANKEN_VERSION}/frankenphp-linux-$(uname -m)" \
         -o /usr/local/bin/frankenphp && \
    chmod +x /usr/local/bin/frankenphp

# Install RoadRunner
RUN composer global require spiral/roadrunner-cli && \
    ln -s /root/.composer/vendor/bin/rr /usr/local/bin/rr

# Install Nginx Unit
RUN curl --output /usr/share/keyrings/nginx-keyring.gpg \
         https://unit.nginx.org/keys/nginx-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/debian/ bookworm unit" \
         > /etc/apt/sources.list.d/unit.list && \
    apt-get update && apt-get install -y unit unit-php || true

# Install Swoole/OpenSwoole
RUN pecl install swoole openswoole && \
    docker-php-ext-enable swoole || true

# Configure Apache with MPM Event + PHP-FPM
RUN if command -v a2enmod > /dev/null; then \
        a2dismod mpm_prefork php${PHP_VERSION} || true; \
        a2enmod mpm_event proxy_fcgi setenvif rewrite ssl headers http2; \
        a2enconf php${PHP_VERSION}-fpm || true; \
    fi

# ========================
# Stage 3: PHP Configuration
# ========================
FROM webservers AS php-config

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
# Stage 5: Dependency Layer
# ========================
FROM server-configs AS dependencies

WORKDIR /app

# Copy dependency manifests
COPY --chown=appuser:appuser composer.json composer.lock* ./
COPY --chown=appuser:appuser package.json package-lock.json* yarn.lock* pnpm-lock.yaml* bun.lockb* .npmrc* .yarnrc* ./

# Install PHP dependencies
RUN --mount=type=cache,target=/root/.composer \
    composer install \
        --no-dev \
        --no-scripts \
        --no-autoloader \
        --prefer-dist \
        --no-interaction \
        --optimize-autoloader

# Detect and install Node dependencies
RUN if [ -f "bun.lockb" ]; then \
        bun install --production; \
    elif [ -f "pnpm-lock.yaml" ]; then \
        pnpm install --prod --frozen-lockfile; \
    elif [ -f "yarn.lock" ]; then \
        yarn install --production --frozen-lockfile; \
    elif [ -f "package-lock.json" ]; then \
        npm ci --production; \
    elif [ -f "package.json" ]; then \
        npm install --production; \
    fi

# ========================
# Stage 6: Application Build
# ========================
FROM dependencies AS builder

# Copy application code
COPY --chown=appuser:appuser . .

# Generate optimized autoloader
RUN composer dump-autoload \
        --optimize \
        --no-dev \
        --classmap-authoritative

# Build frontend assets
RUN if [ -f "vite.config.js" ] || [ -f "vite.config.ts" ]; then \
        npm run build || yarn build || pnpm build || bun run build; \
    elif [ -f "webpack.mix.js" ]; then \
        npm run production || yarn production; \
    elif [ -f "webpack.config.js" ]; then \
        npm run build:prod || yarn build:prod; \
    fi

# Framework-specific optimizations
RUN if [ -f "artisan" ]; then \
        php artisan config:cache && \
        php artisan route:cache && \
        php artisan view:cache && \
        php artisan event:cache; \
    elif [ -f "bin/console" ]; then \
        php bin/console cache:clear --env=prod --no-debug && \
        php bin/console cache:warmup --env=prod --no-debug; \
    fi

# Set correct permissions
RUN find /app -type f -exec chmod 644 {} \; && \
    find /app -type d -exec chmod 755 {} \; && \
    if [ -f "artisan" ]; then chmod +x artisan; fi && \
    if [ -f "bin/console" ]; then chmod +x bin/console; fi && \
    mkdir -p storage/framework/{sessions,views,cache} \
             storage/logs \
             bootstrap/cache && \
    chown -R appuser:appuser storage bootstrap/cache

# ========================
# Stage 7: Universal Entrypoint
# ========================
FROM builder AS runtime

# Create intelligent entrypoint script
RUN cat > /usr/local/bin/docker-entrypoint.sh <<'ENTRYPOINT'
#!/usr/bin/env bash
set -euo pipefail

# Environment variables
SERVER_MODE="${SERVER_MODE:-php-fpm}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
PHP_FPM_PORT="${PHP_FPM_PORT:-9000}"
WORKERS="${WORKERS:-$(nproc)}"

# Framework detection
detect_framework() {
    if [ -f "/app/artisan" ]; then
        echo "laravel"
    elif [ -f "/app/bin/console" ] && [ -d "/app/src" ]; then
        echo "symfony"
    elif [ -f "/app/wp-config.php" ]; then
        echo "wordpress"
    elif [ -f "/app/index.php" ] && [ -d "/app/core" ]; then
        echo "drupal"
    else
        echo "generic"
    fi
}

FRAMEWORK=$(detect_framework)
echo "🔍 Detected framework: $FRAMEWORK"
echo "🚀 Starting server mode: $SERVER_MODE"

# Handle CLI commands
if [ "$#" -gt 0 ]; then
    case "$1" in
        artisan|bin/console|wp|drush|composer|php)
            exec "$@"
            ;;
        bash|sh)
            exec "$@"
            ;;
    esac
fi

# Start appropriate server
case "$SERVER_MODE" in
    php-fpm)
        echo "▶️  Starting PHP-FPM on port $PHP_FPM_PORT"
        exec php-fpm -F
        ;;
    
    nginx)
        echo "▶️  Starting PHP-FPM + Nginx on port $PORT"
        php-fpm -D
        sed -i "s/listen 80/listen $PORT/" /etc/nginx/sites-available/default
        exec nginx -g "daemon off;"
        ;;
    
    apache|apache2)
        echo "▶️  Starting PHP-FPM + Apache on port $PORT"
        php-fpm -D
        sed -i "s/Listen 80/Listen $PORT/" /etc/apache2/ports.conf
        sed -i "s/*:80/*:$PORT/" /etc/apache2/sites-available/000-default.conf
        exec apache2-foreground
        ;;
    
    caddy)
        echo "▶️  Starting PHP-FPM + Caddy on port $PORT"
        php-fpm -D
        sed -i "s/:80/:$PORT/" /etc/caddy/Caddyfile
        exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
        ;;
    
    frankenphp)
        echo "▶️  Starting FrankenPHP on port $PORT"
        cd /app/public 2>/dev/null || cd /app
        exec frankenphp php-server --listen "$HOST:$PORT"
        ;;
    
    roadrunner|rr)
        echo "▶️  Starting RoadRunner on port $PORT"
        
        # Create worker if not exists
        if [ ! -f "/app/worker.php" ]; then
            cat > /app/worker.php <<'WORKER'
<?php
use Spiral\RoadRunner\Worker;
use Spiral\RoadRunner\Http\PSR7Worker;

require __DIR__ . '/vendor/autoload.php';

$worker = Worker::create();
$psr7 = new PSR7Worker($worker);

while ($req = $psr7->waitRequest()) {
    try {
        $psr7->respond(new \Nyholm\Psr7\Response(200, [], 'RoadRunner is working!'));
    } catch (\Throwable $e) {
        $psr7->respond(new \Nyholm\Psr7\Response(500, [], $e->getMessage()));
    }
}
WORKER
        fi
        
        sed -i "s/0.0.0.0:8080/$HOST:$PORT/" /app/.rr.yaml
        sed -i "s/num_workers: 4/num_workers: $WORKERS/" /app/.rr.yaml
        exec rr serve -c /app/.rr.yaml
        ;;
    
    swoole|octane)
        echo "▶️  Starting Swoole/Laravel Octane on port $PORT"
        
        if [ "$FRAMEWORK" = "laravel" ] && [ -f "/app/artisan" ]; then
            exec php artisan octane:start \
                --server=swoole \
                --host="$HOST" \
                --port="$PORT" \
                --workers="$WORKERS"
        else
            # Generic Swoole server
            cat > /tmp/swoole-server.php <<'SWOOLE'
<?php
$http = new Swoole\Http\Server("0.0.0.0", 8080);

$http->set([
    'worker_num' => swoole_cpu_num() * 2,
    'enable_static_handler' => true,
    'document_root' => '/app/public',
]);

$http->on('request', function ($request, $response) {
    $response->header('Content-Type', 'text/html');
    $response->end('<h1>Swoole Server Running</h1>');
});

$http->start();
SWOOLE
            sed -i "s/0.0.0.0/\"$HOST\"/" /tmp/swoole-server.php
            sed -i "s/8080/$PORT/" /tmp/swoole-server.php
            exec php /tmp/swoole-server.php
        fi
        ;;
    
    unit)
        echo "▶️  Starting Nginx Unit on port $PORT"
        sed -i "s/:8080/:$PORT/" /etc/unit/config.json
        unitd --no-daemon --control unix:/var/run/control.unit.sock &
        sleep 2
        curl -X PUT --data-binary @/etc/unit/config.json \
             --unix-socket /var/run/control.unit.sock http://localhost/config
        wait
        ;;
    
    dev|standalone)
        echo "▶️  Starting PHP built-in server on port $PORT (DEVELOPMENT ONLY)"
        
        if [ -d "/app/public" ]; then
            cd /app/public
        else
            cd /app
        fi
        
        exec php -S "$HOST:$PORT" -t .
        ;;
    
    supervisor)
        echo "▶️  Starting Supervisor with multiple services"
        
        # Add Nginx to supervisor if needed
        cat >> /etc/supervisor/supervisord.conf <<'NGINX_SUPERVISOR'

[program:nginx]
command=nginx -g "daemon off;"
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
NGINX_SUPERVISOR
        
        exec supervisord -c /etc/supervisor/supervisord.conf
        ;;
    
    *)
        echo "❌ Unknown SERVER_MODE: $SERVER_MODE"
        echo "Valid modes: php-fpm, nginx, apache, caddy, frankenphp, roadrunner, swoole, unit, dev, supervisor"
        exit 1
        ;;
esac
ENTRYPOINT

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Health check script
RUN cat > /usr/local/bin/healthcheck.sh <<'HEALTHCHECK'
#!/usr/bin/env bash
set -e

PORT="${PORT:-8080}"
PHP_FPM_PORT="${PHP_FPM_PORT:-9000}"

case "${SERVER_MODE:-php-fpm}" in
    php-fpm)
        cgi-fcgi -bind -connect 127.0.0.1:$PHP_FPM_PORT || exit 1
        ;;
    *)
        curl -f http://localhost:$PORT/ || exit 1
        ;;
esac
HEALTHCHECK

RUN chmod +x /usr/local/bin/healthcheck.sh

# ========================
# Stage 8: Production Release
# ========================
FROM runtime AS production

# Remove development tools
RUN if command -v apt-get > /dev/null; then \
        apt-get purge -y build-essential autoconf pkg-config && \
        apt-get autoremove -y && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    fi

# Security hardening
RUN rm -rf /tmp/* /var/tmp/* && \
    find /app -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find /app -name ".env.example" -delete 2>/dev/null || true

USER appuser

EXPOSE 8080 9000

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["php-fpm"]

# ========================
# Stage 9: Development Mode
# ========================
FROM runtime AS development

USER root

# Install development tools
RUN if command -v apt-get > /dev/null; then \
        apt-get update && apt-get install -y --no-install-recommends \
            vim nano less \
            strace ltrace \
            mysql-client postgresql-client redis-tools \
        && rm -rf /var/lib/apt/lists/*; \
    else \
        apk add --no-cache \
            vim nano less \
            strace ltrace \
            mysql-client postgresql-client redis; \
    fi

# Install Xdebug for development
RUN pecl install xdebug && docker-php-ext-enable xdebug

# Xdebug configuration
RUN { \
        echo "[xdebug]"; \
        echo "xdebug.mode=debug,coverage,develop"; \
        echo "xdebug.start_with_request=yes"; \
        echo "xdebug.client_host=host.docker.internal"; \
        echo "xdebug.client_port=9003"; \
        echo "xdebug.idekey=PHPSTORM"; \
        echo "xdebug.log=/var/log/php/xdebug.log"; \
    } > /usr/local/etc/php/conf.d/xdebug.ini

# Enable development PHP settings
RUN { \
        echo "[PHP]"; \
        echo "display_errors = On"; \
        echo "display_startup_errors = On"; \
        echo "error_reporting = E_ALL"; \
        echo "opcache.validate_timestamps = 1"; \
        echo "opcache.revalidate_freq = 0"; \
    } > /usr/local/etc/php/conf.d/99-development.ini

USER appuser

ENV APP_ENV=development \
    APP_DEBUG=true

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["dev"]

# ========================
# Stage 10: Specialized Laravel
# ========================
FROM production AS laravel

USER root

# Install Laravel-specific tools
RUN composer global require laravel/installer laravel/envoy

# Laravel Horizon support
RUN pecl install mongodb && docker-php-ext-enable mongodb || true

# Laravel Queue Worker configuration
RUN { \
        echo "[program:laravel-worker]"; \
        echo "process_name=%(program_name)s_%(process_num)02d"; \
        echo "command=php /app/artisan queue:work --sleep=3 --tries=3 --max-time=3600"; \
        echo "autostart=true"; \
        echo "autorestart=true"; \
        echo "stopasgroup=true"; \
        echo "killasgroup=true"; \
        echo "user=appuser"; \
        echo "numprocs=4"; \
        echo "redirect_stderr=true"; \
        echo "stdout_logfile=/app/storage/logs/worker.log"; \
        echo "stopwaitsecs=3600"; \
    } > /etc/supervisor/conf.d/laravel-worker.conf

# Laravel Scheduler
RUN { \
        echo "[program:laravel-scheduler]"; \
        echo "command=bash -c 'while true; do php /app/artisan schedule:run --verbose --no-interaction & sleep 60; done'"; \
        echo "autostart=true"; \
        echo "autorestart=true"; \
        echo "user=appuser"; \
        echo "redirect_stderr=true"; \
        echo "stdout_logfile=/app/storage/logs/scheduler.log"; \
    } > /etc/supervisor/conf.d/laravel-scheduler.conf

USER appuser

LABEL org.opencontainers.image.title="Laravel Application" \
      org.opencontainers.image.description="Production-ready Laravel with queue workers"

# ========================
# Stage 11: Specialized Symfony
# ========================
FROM production AS symfony

USER root

# Install Symfony CLI
RUN curl -1sLf 'https://dl.cloudsmith.io/public/symfony/stable/setup.deb.sh' | bash && \
    apt-get install -y symfony-cli || \
    (wget https://github.com/symfony-cli/symfony-cli/releases/latest/download/symfony-cli_linux_amd64.tar.gz && \
     tar -xzf symfony-cli_linux_amd64.tar.gz -C /usr/local/bin && \
     rm symfony-cli_linux_amd64.tar.gz)

# Symfony Messenger Worker
RUN { \
        echo "[program:symfony-messenger]"; \
        echo "command=php /app/bin/console messenger:consume async --time-limit=3600"; \
        echo "user=appuser"; \
        echo "numprocs=2"; \
        echo "autostart=true"; \
        echo "autorestart=true"; \
        echo "process_name=%(program_name)s_%(process_num)02d"; \
    } > /etc/supervisor/conf.d/symfony-messenger.conf

USER appuser

LABEL org.opencontainers.image.title="Symfony Application" \
      org.opencontainers.image.description="Production-ready Symfony with Messenger workers"

# ========================
# Stage 12: WordPress Optimized
# ========================
FROM production AS wordpress

USER root

# Install WordPress CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp

# Install additional PHP extensions for WordPress
RUN install-php-extensions \
        gmp \
        ssh2

# WordPress-specific Nginx config
RUN { \
        echo "server {"; \
        echo "    listen 80;"; \
        echo "    root /app;"; \
        echo "    index index.php;"; \
        echo ""; \
        echo "    location = /favicon.ico { log_not_found off; access_log off; }"; \
        echo "    location = /robots.txt { log_not_found off; access_log off; allow all; }"; \
        echo "    location ~* \.(css|gif|ico|jpeg|jpg|js|png)$ { expires max; log_not_found off; }"; \
        echo ""; \
        echo "    location / {"; \
        echo "        try_files \$uri \$uri/ /index.php?\$args;"; \
        echo "    }"; \
        echo ""; \
        echo "    location ~ \.php$ {"; \
        echo "        include fastcgi_params;"; \
        echo "        fastcgi_intercept_errors on;"; \
        echo "        fastcgi_pass 127.0.0.1:9000;"; \
        echo "        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;"; \
        echo "    }"; \
        echo ""; \
        echo "    location ~* /(?:uploads|files)/.*\.php$ { deny all; }"; \
        echo "}"; \
    } > /etc/nginx/sites-available/wordpress.conf

# Configure PHP for WordPress
RUN { \
        echo "upload_max_filesize = 256M"; \
        echo "post_max_size = 256M"; \
        echo "memory_limit = 512M"; \
        echo "max_execution_time = 600"; \
        echo "max_input_vars = 3000"; \
        echo "max_input_time = 1000"; \
    } > /usr/local/etc/php/conf.d/wordpress.ini

USER appuser

LABEL org.opencontainers.image.title="WordPress Application" \
      org.opencontainers.image.description="Production-ready WordPress with WP-CLI"

# ========================
# Stage 13: Multi-Server (All-in-One)
# ========================
FROM runtime AS multi-server

USER root

# Create master entrypoint for multi-server orchestration
RUN cat > /usr/local/bin/multi-server-entrypoint.sh <<'MULTISERVER'
#!/usr/bin/env bash
set -euo pipefail

SERVERS="${SERVERS:-php-fpm,nginx}"
PORT="${PORT:-8080}"

echo "🚀 Starting multi-server mode: $SERVERS"

start_server() {
    local server=$1
    case "$server" in
        php-fpm)
            php-fpm -D
            echo "✅ PHP-FPM started on port 9000"
            ;;
        nginx)
            sed -i "s/listen 80/listen $PORT/" /etc/nginx/sites-available/default
            nginx -g "daemon off;" &
            echo "✅ Nginx started on port $PORT"
            ;;
        apache)
            apache2-foreground &
            echo "✅ Apache started"
            ;;
        caddy)
            caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
            echo "✅ Caddy started"
            ;;
        cron)
            cron -f &
            echo "✅ Cron started"
            ;;
        supervisor)
            supervisord -c /etc/supervisor/supervisord.conf &
            echo "✅ Supervisor started"
            ;;
    esac
}

IFS=',' read -ra SERVER_ARRAY <<< "$SERVERS"
for server in "${SERVER_ARRAY[@]}"; do
    start_server "$(echo $server | xargs)"
done

wait
MULTISERVER

RUN chmod +x /usr/local/bin/multi-server-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/multi-server-entrypoint.sh"]

# ========================
# Stage 14: Serverless/Lambda Ready
# ========================
FROM production AS serverless

USER root

# Install AWS Lambda Runtime Interface Client
RUN if command -v apt-get > /dev/null; then \
        apt-get update && apt-get install -y --no-install-recommends \
            libcurl4-openssl-dev \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# Install Bref layers simulation (for local testing)
RUN composer global require bref/bref

# Lambda handler wrapper
RUN cat > /usr/local/bin/lambda-handler.sh <<'LAMBDA'
#!/usr/bin/env bash
set -e

export AWS_LAMBDA_RUNTIME_API="${AWS_LAMBDA_RUNTIME_API:-localhost:9001}"

if [ -f "/app/lambda.php" ]; then
    exec php /app/lambda.php
elif [ -f "/app/index.php" ]; then
    exec php /app/index.php
else
    echo "No lambda handler found"
    exit 1
fi
LAMBDA

RUN chmod +x /usr/local/bin/lambda-handler.sh

ENTRYPOINT ["/usr/local/bin/lambda-handler.sh"]

LABEL org.opencontainers.image.title="PHP Serverless/Lambda" \
      org.opencontainers.image.description="AWS Lambda compatible PHP runtime"

# ========================
# Stage 15: Performance Testing
# ========================
FROM runtime AS benchmark

USER root

# Install performance testing tools
RUN if command -v apt-get > /dev/null; then \
        apt-get update && apt-get install -y --no-install-recommends \
            apache2-utils \
            siege \
            wrk \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# Install k6 for load testing
RUN if [ "$(uname -m)" = "x86_64" ]; then \
        wget https://github.com/grafana/k6/releases/latest/download/k6-linux-amd64.tar.gz && \
        tar -xzf k6-linux-amd64.tar.gz && \
        mv k6-*/k6 /usr/local/bin/ && \
        rm -rf k6-*; \
    fi

# Benchmark script
RUN cat > /usr/local/bin/run-benchmarks.sh <<'BENCHMARK'
#!/usr/bin/env bash
set -e

URL="${BENCHMARK_URL:-http://localhost:8080}"
REQUESTS="${BENCHMARK_REQUESTS:-10000}"
CONCURRENCY="${BENCHMARK_CONCURRENCY:-100}"

echo "🔥 Running benchmarks against: $URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v ab > /dev/null; then
    echo "📊 Apache Bench Results:"
    ab -n "$REQUESTS" -c "$CONCURRENCY" "$URL"
    echo ""
fi

if command -v siege > /dev/null; then
    echo "🎯 Siege Results:"
    siege -c "$CONCURRENCY" -t 30s "$URL"
    echo ""
fi

if command -v wrk > /dev/null; then
    echo "⚡ WRK Results:"
    wrk -t4 -c "$CONCURRENCY" -d30s "$URL"
fi
BENCHMARK

RUN chmod +x /usr/local/bin/run-benchmarks.sh

USER appuser

CMD ["/usr/local/bin/run-benchmarks.sh"]

# ========================
# Stage 16: CI/CD Ready
# ========================
FROM runtime AS ci

USER root

# Install CI/CD tools
RUN if command -v apt-get > /dev/null; then \
        apt-get update && apt-get install -y --no-install-recommends \
            git \
            openssh-client \
            rsync \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# Install PHPUnit, PHPCS, PHPStan
RUN composer global require \
        phpunit/phpunit \
        squizlabs/php_codesniffer \
        phpstan/phpstan \
        friendsofphp/php-cs-fixer \
        vimeo/psalm

# Install Node testing tools
RUN npm install -g \
        jest \
        @playwright/test \
        eslint \
        prettier

# CI runner script
RUN cat > /usr/local/bin/ci-runner.sh <<'CIRUNNER'
#!/usr/bin/env bash
set -e

echo "🧪 Running CI/CD Pipeline"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd /app

# PHP Tests
if [ -f "phpunit.xml" ] || [ -f "phpunit.xml.dist" ]; then
    echo "🔍 Running PHPUnit tests..."
    phpunit --coverage-text
fi

# Code Standards
if [ -f "phpcs.xml" ] || [ -f "phpcs.xml.dist" ]; then
    echo "🎨 Checking code standards (PHPCS)..."
    phpcs
fi

# Static Analysis
if [ -f "phpstan.neon" ] || [ -f "phpstan.neon.dist" ]; then
    echo "🔬 Running static analysis (PHPStan)..."
    phpstan analyse
fi

# JavaScript Tests
if [ -f "jest.config.js" ]; then
    echo "🧪 Running Jest tests..."
    jest
fi

# Linting
if [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ]; then
    echo "🧹 Running ESLint..."
    eslint .
fi

echo "✅ All CI checks passed!"
CIRUNNER

RUN chmod +x /usr/local/bin/ci-runner.sh

USER appuser

CMD ["/usr/local/bin/ci-runner.sh"]

# ========================
# Stage 17: Security Scanner
# ========================
FROM runtime AS security

USER root

# Install security scanning tools
RUN composer global require \
        enlightn/security-checker \
        sensiolabs/security-checker || true

# Install Trivy for vulnerability scanning
RUN if [ "$(uname -m)" = "x86_64" ]; then \
        wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add - && \
        echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | tee -a /etc/apt/sources.list.d/trivy.list && \
        apt-get update && apt-get install -y trivy; \
    fi

# Security audit script
RUN cat > /usr/local/bin/security-audit.sh <<'SECURITY'
#!/usr/bin/env bash
set -e

echo "🔒 Running Security Audit"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd /app

# Composer dependencies
if [ -f "composer.lock" ]; then
    echo "🔍 Checking PHP dependencies for vulnerabilities..."
    composer audit || security-checker security:check composer.lock || true
fi

# NPM dependencies
if [ -f "package-lock.json" ]; then
    echo "🔍 Checking Node dependencies for vulnerabilities..."
    npm audit || true
fi

# File permissions audit
echo "🔐 Checking file permissions..."
find /app -type f -perm /o+w -ls || true

echo "✅ Security audit complete!"
SECURITY

RUN chmod +x /usr/local/bin/security-audit.sh

USER appuser

CMD ["/usr/local/bin/security-audit.sh"]

# ========================
# Stage 18: Monitoring & Observability
# ========================
FROM production AS monitoring

USER root

# Install monitoring tools
RUN pecl install apcu_bc datadog_trace && \
    docker-php-ext-enable apcu datadog_trace || true

# New Relic PHP Agent
RUN if [ "$(uname -m)" = "x86_64" ]; then \
        curl -L https://download.newrelic.com/php_agent/release/newrelic-php5-linux-amd64.tar.gz | tar -C /tmp -zx && \
        export NR_INSTALL_USE_CP_NOT_LN=1 && \
        export NR_INSTALL_SILENT=1 && \
        /tmp/newrelic-php5-*/newrelic-install install || true && \
        rm -rf /tmp/newrelic-php5-* /tmp/nrinstall*; \
    fi

# Prometheus PHP-FPM exporter
RUN wget -O /usr/local/bin/phpfpm_exporter \
        https://github.com/hipages/php-fpm_exporter/releases/latest/download/php-fpm_exporter_linux_amd64 && \
    chmod +x /usr/local/bin/phpfpm_exporter || true

# Metrics endpoint configuration
RUN { \
        echo "[program:phpfpm-exporter]"; \
        echo "command=/usr/local/bin/phpfpm_exporter --phpfpm.scrape-uri tcp://127.0.0.1:9000/status"; \
        echo "autostart=true"; \
        echo "autorestart=true"; \
        echo "stdout_logfile=/dev/stdout"; \
        echo "stdout_logfile_maxbytes=0"; \
    } > /etc/supervisor/conf.d/phpfpm-exporter.conf || true

USER appuser

EXPOSE 9253

LABEL org.opencontainers.image.title="PHP with Monitoring" \
      org.opencontainers.image.description="PHP with APM and metrics exporters"

# ========================
# Stage 19: Final Release (Meta)
# ========================
FROM production AS release

# Metadata labels (OCI compliant)
LABEL org.opencontainers.image.title="Universal PHP Dexfile" \
      org.opencontainers.image.description="Production-ready PHP container with multiple web servers" \
      org.opencontainers.image.vendor="Dexnore" \
      org.opencontainers.image.authors="Dexnore Team" \
      org.opencontainers.image.documentation="https://github.com/dexnore/dexfile" \
      org.opencontainers.image.source="https://github.com/dexnore/dexfile" \
      org.opencontainers.image.licenses="MIT" \
      com.dexnore.php.version="${PHP_VERSION}" \
      com.dexnore.base.os="${BASE_OS}" \
      com.dexnore.features="php-fpm,nginx,apache,caddy,frankenphp,roadrunner,swoole,unit"

# BuildKit network restrictions for production builds
LABEL moby.buildkit.frontend.network.none="false"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

# Dexfile metadata
LABEL com.dexnore.dexfile.version="1.0.0" \
      com.dexnore.dexfile.syntax="dexnore/dexfile:1" \
      com.dexnore.dexfile.build-date="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

USER appuser
WORKDIR /app

EXPOSE 8080 9000

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["php-fpm"]

# ========================
# Build Targets Summary
# ========================
# Build specific targets with:
# docker build --target <stage> -t myapp:<stage> .
#
# Available stages:
# - production       : Default production build with PHP-FPM
# - development      : Development build with Xdebug
# - laravel          : Laravel optimized with queue workers
# - symfony          : Symfony optimized with Messenger
# - wordpress        : WordPress optimized with WP-CLI
# - multi-server     : Multiple servers running simultaneously
# - serverless       : AWS Lambda compatible runtime
# - benchmark        : Performance testing tools included
# - ci               : CI/CD pipeline tools
# - security         : Security scanning tools
# - monitoring       : APM and metrics exporters
# - release          : Final production release (same as production)
#
# Environment Variables:
# - SERVER_MODE      : php-fpm|nginx|apache|caddy|frankenphp|roadrunner|swoole|unit|dev
# - HOST             : Bind address (default: 0.0.0.0)
# - PORT             : Server port (default: 8080)
# - WORKERS          : Number of workers for async servers
# - PHP_MEMORY_LIMIT : PHP memory limit
# - SERVERS          : Comma-separated list for multi-server mode
# ========================