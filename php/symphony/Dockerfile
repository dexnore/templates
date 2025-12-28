# syntax=docker/dockerfile:1.7

############################
# Stage 1: Base Runtime
############################
FROM php:8.3-fpm-alpine AS base

ENV APP_ENV=prod \
    APP_DEBUG=0 \
    PHP_INI_DIR=/usr/local/etc/php

# Runtime dependencies + fcgi for reliable healthchecks
RUN apk add --no-cache \
        bash \
        tzdata \
        ca-certificates \
        fcgi \
    && update-ca-certificates

# PHP extension installer
ARG IPE_VERSION=1.6.0
ADD https://github.com/mlocati/docker-php-extension-installer/releases/download/${IPE_VERSION}/install-php-extensions /usr/local/bin/install-php-extensions

RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions \
        opcache apcu intl pdo_mysql pdo_pgsql redis zip gd bcmath exif pcntl \
    && rm -f /usr/local/bin/install-php-extensions

############################
# PHP Production Config
############################
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY <<'EOF' $PHP_INI_DIR/conf.d/zz-symfony.ini
expose_php = 0
memory_limit = 512M
max_execution_time = 60
realpath_cache_size = 4096K
realpath_cache_ttl = 600

; Opcache (tuned for Symfony Preloading)
opcache.enable = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 0
opcache.preload = /var/www/html/config/preload.php
opcache.preload_user = www-data

; APCu for metadata and result caching
apc.enable_cli = 1
EOF

############################
# Stage 2: Builder
############################
FROM base AS builder
WORKDIR /app

COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock symfony.lock ./

RUN --mount=type=cache,target=/tmp/cache/composer \
    COMPOSER_CACHE_DIR=/tmp/cache/composer \
    composer install --no-dev --no-interaction --no-scripts --prefer-dist --no-autoloader

COPY . .

# Run post-install scripts (warm up cache, build assets)
RUN composer dump-autoload --optimize --classmap-authoritative \
    && APP_ENV=prod APP_DEBUG=0 composer run-script --no-dev post-install-cmd

############################
# Stage 3: Final Runtime
############################
FROM base AS final
WORKDIR /var/www/html

# Copy from builder using the built-in www-data user
COPY --from=builder --chown=www-data:www-data /app /var/www/html

# Setup Symfony writable directories
RUN mkdir -p var/cache var/log \
    && chown -R www-data:www-data var \
    && chmod -R 775 var

USER www-data

EXPOSE 9000

# Healthcheck hits the FPM ping/status (requires 'ping.path' in FPM config)
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1

STOPSIGNAL SIGQUIT

CMD ["php-fpm"]