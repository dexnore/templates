# syntax=docker/dockerfile:1.7

############################
# Stage 1: Base Runtime
############################
FROM php:8.3-cli-alpine AS base

ENV APP_ENV=production \
    PHP_INI_DIR=/usr/local/etc/php \
    PHP_OUTPUT_BUFFERING=Off \
    COMPOSER_ALLOW_SUPERUSER=1

# Minimal runtime dependencies
RUN apk add --no-cache \
        bash \
        tzdata \
        ca-certificates \
        curl \
    && update-ca-certificates

# PHP extension installer
ARG IPE_VERSION=1.6.0
ADD https://github.com/mlocati/docker-php-extension-installer/releases/download/${IPE_VERSION}/install-php-extensions \
    /usr/local/bin/install-php-extensions

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
    && rm -f /usr/local/bin/install-php-extensions

# PHP configuration for Octane + RoadRunner
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY <<'EOF' $PHP_INI_DIR/conf.d/zz-octane.ini
expose_php = 0
memory_limit = 512M
max_execution_time = 0
output_buffering = Off
variables_order = "EGPCS"

; Opcache is mandatory for Octane persistence
opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 0

; Required for graceful RoadRunner worker shutdown
pcntl.async_signals = 1
EOF

############################
# Stage 2: RoadRunner Binary
############################
FROM ghcr.io/roadrunner-server/roadrunner:2024 AS roadrunner

############################
# Stage 3: Builder
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
RUN composer dump-autoload \
        --optimize \
        --classmap-authoritative

############################
# Stage 4: Final Runtime
############################
FROM base AS final
WORKDIR /app

# Non-root runtime user
RUN addgroup -g 1000 app \
    && adduser -D -u 1000 -G app app \
    && mkdir -p /app/storage /app/bootstrap/cache

# RoadRunner binary
COPY --from=roadrunner /usr/bin/rr /usr/local/bin/rr

# Application
COPY --from=builder --chown=app:app /app /app

# Laravel writable paths
RUN chmod -R 775 /app/storage /app/bootstrap/cache \
    && chown -R app:app /app/storage /app/bootstrap/cache

USER app
EXPOSE 9000 6001

# Healthcheck against Octane HTTP server
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
    CMD curl -f http://127.0.0.1:9000/health || exit 1

STOPSIGNAL SIGTERM

# RoadRunner MUST remain PID 1 (no supervisor)
CMD ["php", "artisan", "octane:start", \
     "--server=roadrunner", \
     "--host=0.0.0.0", \
     "--port=9000", \
     "--rpc-port=6001", \
     "--workers=auto", \
     "--max-requests=1000"]
