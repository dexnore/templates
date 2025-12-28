# syntax=docker/dockerfile:1.7

############################
# Stage 1: Base PHP Unit
############################
FROM unit:1.32.1-php8.3 AS base

ENV APP_ENV=production \
    PHP_INI_DIR=/usr/local/etc/php

# Minimal runtime dependencies; installer handles dev-deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget ca-certificates unzip curl \
    && rm -rf /var/lib/apt/lists/*

# PHP Extension Installer
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/install-php-extensions
RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions \
        opcache pdo_mysql pdo_pgsql redis zip gd intl bcmath exif pcntl apcu \
    && rm /usr/local/bin/install-php-extensions

# PHP Production Configuration
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

############################
# Stage 2: Builder (Composer)
############################
FROM base AS builder
WORKDIR /app

# Install Composer
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock ./

# Use cache for faster rebuilds
RUN --mount=type=cache,target=/tmp/cache/composer \
    COMPOSER_CACHE_DIR=/tmp/cache/composer \
    composer install --no-dev --no-interaction --no-scripts --prefer-dist --no-autoloader

COPY . .
RUN composer dump-autoload --optimize --classmap-authoritative

############################
# Stage 3: Final Runtime
############################
FROM base AS final
WORKDIR /var/www/html

# Non-root user and Unit directories
RUN useradd -u 1000 -m -s /bin/bash appuser && \
    mkdir -p /var/lib/unit /var/run/unit /var/log/unit && \
    chown -R appuser:appuser /var/www/html /var/lib/unit /var/run/unit /var/log/unit

# Copy application code
COPY --from=builder --chown=appuser:appuser /app /var/www/html

# NGINX Unit JSON Configuration
COPY --chown=appuser:appuser <<'EOF' /docker-entrypoint.d/config.json
{
    "listeners": {
        "*:80": {
            "pass": "routes"
        },
        "*:9191": {
            "pass": "status"
        }
    },
    "routes": [
        {
            "match": { "uri": ["*.php", "*.php/*"] },
            "action": { "pass": "applications/php" }
        },
        {
            "action": {
                "share": "/var/www/html/public$uri",
                "fallback": { "pass": "applications/php/index.php" }
            }
        }
    ],
    "applications": {
        "php": {
            "type": "php",
            "user": "appuser",
            "group": "appuser",
            "root": "/var/www/html/public/",
            "script": "index.php",
            "processes": {
                "max": 20,
                "spare": 5,
                "idle_timeout": 60
            }
        }
    },
    "status": {
        "allow": ["127.0.0.1"],
        "prometheus": true
    },
    "access_log": "/var/log/unit/access.log",
    "error_log": "/var/log/unit/error.log"
}
EOF

USER appuser
EXPOSE 80 9191

# Healthcheck targeting the main application
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["unitd", "--no-daemon", "--control", "unix:/var/run/unit/control.unit.sock"]
