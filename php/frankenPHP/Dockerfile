# syntax=docker/dockerfile:1.7

############################
# Stage 1: Base runtime
############################
FROM dunglas/frankenphp:1.2-php8.3-alpine AS base

# Set production environment variables
ENV APP_ENV=production \
    PHP_INI_DIR=/usr/local/etc/php \
    PHP_OUTPUT_BUFFERING=Off \
    FRANKENPHP_CONFIG="worker /app/public/index.php" \
    FRANKENPHP_NUM_THREADS=4

# Install runtime dependencies
RUN apk add --no-cache \
        ca-certificates \
        tzdata \
        bash \
        wget \
    && update-ca-certificates

# PHP extension installer
ARG IPE_VERSION=1.6.0
ADD https://github.com/mlocati/docker-php-extension-installer/releases/download/${IPE_VERSION}/install-php-extensions /usr/local/bin/install-php-extensions
RUN chmod +x /usr/local/bin/install-php-extensions

# Install PHP extensions and remove installer
RUN install-php-extensions \
        opcache \
        pdo_mysql \
        pdo_pgsql \
        redis \
        zip \
        intl \
        bcmath \
        exif \
        pcntl \
        apcu \
    && rm /usr/local/bin/install-php-extensions

############################
# Stage 2: PHP production config
############################
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY <<'EOF' $PHP_INI_DIR/conf.d/zz-production.ini
expose_php = 0
memory_limit = 512M
output_buffering = Off
realpath_cache_size = 4096K
realpath_cache_ttl = 600
max_execution_time = 0
opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 0
apc.enable_cli = 1
EOF

############################
# Stage 3: Builder (Composer)
############################
FROM base AS builder
WORKDIR /app

# Copy Composer binary
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

# Copy Composer files and install dependencies using cache
COPY composer.json composer.lock ./
RUN --mount=type=cache,target=/tmp/cache/composer \
    COMPOSER_CACHE_DIR=/tmp/cache/composer \
    composer install --no-dev --no-scripts --prefer-dist --no-autoloader --no-interaction

# Copy application code and optimize autoloader
COPY . .
RUN composer dump-autoload --optimize --classmap-authoritative

############################
# Stage 4: Final runtime
############################
FROM base AS final
WORKDIR /app

# Create non-root user and necessary directories
RUN addgroup -g 1000 app && adduser -D -u 1000 -G app app \
    && mkdir -p /data/caddy /config/caddy /tmp \
    && chown -R app:app /app /data/caddy /config/caddy /tmp

# Copy application from builder
COPY --from=builder --chown=app:app /app /app

############################
# Caddy / FrankenPHP config
############################
COPY --chown=app:app <<'EOF' /etc/caddy/Caddyfile
{
    admin off
    log {
        output stdout
        format json
    }
    frankenphp {
        num_threads {env.FRANKENPHP_NUM_THREADS}
    }
    order php_server before file_server
}

:80 {
    root * /app/public
    encode zstd gzip

    # Security hardening
    header {
        -Server
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }

    php_server {
        index index.php
        worker /app/public/index.php {env.FRANKENPHP_NUM_THREADS}
    }

    file_server
}
EOF

# Final image settings
USER app
EXPOSE 80 443 443/udp
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1/ || exit 1

ENTRYPOINT ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
