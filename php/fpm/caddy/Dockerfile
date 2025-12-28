# syntax=docker/dockerfile:1.7

############################
# Stage 1: Base PHP-FPM
############################
FROM php:8.3-fpm-alpine AS base

ENV APP_ENV=production \
    PHP_INI_DIR=/usr/local/etc/php \
    PHP_OUTPUT_BUFFERING=Off

# Runtime dependencies + fcgi for healthcheck
RUN apk add --no-cache \
        bash \
        fcgi \
        linux-headers \
        tzdata \
        wget \
    && update-ca-certificates

# PHP Extension Installer
ARG IPE_VERSION=1.6.0
ADD https://github.com/mlocati/docker-php-extension-installer/releases/download/${IPE_VERSION}/install-php-extensions /usr/local/bin/install-php-extensions
RUN chmod +x /usr/local/bin/install-php-extensions

# Install PHP extensions in a single clean layer
RUN install-php-extensions \
        opcache pdo_mysql pdo_pgsql redis zip gd intl bcmath exif pcntl apcu \
    && rm /usr/local/bin/install-php-extensions

# PHP Production Configuration
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY <<'EOF' $PHP_INI_DIR/conf.d/zz-production.ini
expose_php = 0
memory_limit = 512M
upload_max_filesize = 50M
post_max_size = 50M
max_execution_time = 60
realpath_cache_size = 4096K
realpath_cache_ttl = 600

opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0
apc.enable_cli=1
EOF

# FPM tuning & worker logging
COPY <<'EOF' /usr/local/etc/php-fpm.d/zz-fpm-tuning.conf
[www]
user = app
group = app
listen = 9000

pm = dynamic
pm.max_children = 50
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 20
pm.max_requests = 500
pm.status_path = /status

clear_env = no
catch_workers_output = yes
decorate_workers_output = no
EOF

############################
# Stage 2: Builder (Composer)
############################
FROM base AS builder
WORKDIR /app

# Copy composer binary and lockfiles
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock ./

# Mount cache for faster iterative builds
RUN --mount=type=cache,target=/tmp/cache/composer \
    COMPOSER_CACHE_DIR=/tmp/cache/composer \
    composer install --no-dev --no-interaction --no-scripts --prefer-dist --no-autoloader

# Copy app source and optimize autoloading
COPY . .
RUN composer dump-autoload --optimize --classmap-authoritative

############################
# Stage 3: Caddy (Web Server)
############################
FROM caddy:2-alpine AS caddy-final
WORKDIR /var/www/html

COPY <<'EOF' /etc/caddy/Caddyfile
{
    admin off
    auto_https off
    log {
        output stdout
        format json
    }
}

:80 {
    root * /var/www/html/public
    encode zstd gzip

    header {
        -Server
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }

    # Proxying to the PHP-FPM service container
    php_fastcgi php-fpm:9000 {
        root /var/www/html/public
        try_files {path} {path}/index.php =404
    }

    file_server
}
EOF

# Copy only public assets to Caddy
COPY --from=builder /app/public /var/www/html/public

############################
# Stage 4: PHP-FPM Final
############################
FROM base AS fpm-final
WORKDIR /var/www/html

# Create non-root user and setup permissions
RUN addgroup -g 1000 app && adduser -D -u 1000 -G app app \
    && mkdir -p /tmp \
    && chown -R app:app /var/www/html /tmp

# Copy full application from builder
COPY --from=builder --chown=app:app /app /var/www/html

USER app
EXPOSE 9000

# Healthcheck verifies FastCGI pool via /status
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
    CMD SCRIPT_NAME=/status SCRIPT_FILENAME=/status REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1

CMD ["php-fpm"]
