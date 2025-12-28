# syntax=docker/dockerfile:1.7

############################
# Stage 1: Base Runtime
############################
FROM php:8.3-cli-alpine AS base

ENV APP_ENV=production \
    PHP_INI_DIR=/usr/local/etc/php \
    PHP_OUTPUT_BUFFERING=Off

# Minimal runtime dependencies only
RUN apk add --no-cache \
        bash \
        tzdata \
        ca-certificates \
        linux-headers \
    && update-ca-certificates

############################
# PHP Extensions
############################
ARG IPE_VERSION=1.6.0
ADD https://github.com/mlocati/docker-php-extension-installer/releases/download/${IPE_VERSION}/install-php-extensions /usr/local/bin/install-php-extensions

RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions \
        opcache \
        pdo_mysql \
        pdo_pgsql \
        redis \
        zip \
        gd \
        intl \
        bcmath \
        exif \
        pcntl \
        sockets \
        swoole \
    && rm -f /usr/local/bin/install-php-extensions

############################
# PHP Production Config
# (Long-running Swoole safe)
############################
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY <<'EOF' $PHP_INI_DIR/conf.d/zz-swoole.ini
expose_php = 0
memory_limit = 512M
max_execution_time = 0
output_buffering = Off
variables_order = "EGPCS"

; Opcache (CLI mandatory for Swoole)
opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 0

; Swoole requirements
swoole.use_shortname = Off
EOF

############################
# Stage 2: Builder
############################
FROM base AS builder
WORKDIR /app

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
RUN composer dump-autoload --optimize --classmap-authoritative

############################
# Stage 3: Final Runtime
############################
FROM base AS final
WORKDIR /app

# Non-root runtime user
RUN addgroup -g 1000 app && adduser -D -u 1000 -G app app

COPY --from=builder --chown=app:app /app /app

USER app
EXPOSE 9000

# HTTP-based Swoole healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:9000/health || exit 1

STOPSIGNAL SIGTERM

# Exec form so PHP/Swoole receives signals correctly
CMD ["php", "swoole.php"]
