# syntax=docker/dockerfile:1.7

############################
# Stage 1: Base Runtime
############################
FROM serversideup/php:8.3-fpm-nginx-alpine AS base

# ServerSideUp runtime configuration (consumed by entrypoint)
ENV APP_ENV=production \
    SSL_MODE=off \
    PHP_FPM_PM=dynamic \
    PHP_FPM_PM_MAX_CHILDREN=50 \
    PHP_FPM_PM_START_SERVERS=10 \
    PHP_FPM_PM_MIN_SPARE_SERVERS=5 \
    PHP_FPM_PM_MAX_SPARE_SERVERS=20 \
    PHP_FPM_PM_MAX_REQUESTS=500 \
    PHP_OPCACHE_ENABLE=1 \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=0

# Install missing PHP extensions only
RUN install-php-extensions \
        redis \
        bcmath \
        exif \
        pcntl

# PHP runtime configuration (limits & behavior only)
COPY <<'EOF' /usr/local/etc/php/conf.d/zz-app-production.ini
expose_php = 0
memory_limit = 512M
upload_max_filesize = 50M
post_max_size = 50M
max_execution_time = 60

realpath_cache_size = 4096K
realpath_cache_ttl = 600

opcache.enable = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 0
EOF

############################
# Stage 2: Builder
############################
FROM base AS builder
WORKDIR /var/www/html

COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock ./

RUN --mount=type=cache,target=/tmp/cache/composer \
    COMPOSER_CACHE_DIR=/tmp/cache/composer \
    composer install \
        --no-dev \
        --no-interaction \
        --no-scripts \
        --prefer-dist \
        --no-autoloader

COPY . .
RUN composer dump-autoload \
        --optimize \
        --classmap-authoritative

############################
# Stage 3: Final Runtime
############################
FROM base AS final
WORKDIR /var/www/html

# Copy application with correct ownership
COPY --from=builder --chown=www-data:www-data /var/www/html /var/www/html

# Laravel-specific writable dirs (ownership only, no chmod storm)
RUN mkdir -p storage bootstrap/cache \
 && chown -R www-data:www-data storage bootstrap/cache

EXPOSE 80 443

# Healthcheck via Nginx (real user path)
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1/ || exit 1

# DO NOT override CMD or ENTRYPOINT
# s6-overlay will start nginx + php-fpm correctly
CMD []
