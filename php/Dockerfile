# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

# ========================
# Stage 1: Base image & tools
# ========================
FROM php:8.2-fpm AS base

ARG PHP_EXTENSIONS="pdo pdo_mysql zip mbstring exif pcntl bcmath gd xml"

ENV HOME=/root \
    DEBIAN_FRONTEND=noninteractive \
    PATH=/root/.composer/vendor/bin:/usr/local/bin:$PATH \
    COMPOSER_ALLOW_SUPERUSER=1 \
    PHP_SERVE_MODE=PRODUCTION \
    APP_PORT=9000

WORKDIR /home/dexfile/app

# Create non-root user early
RUN groupadd -r dexnore && useradd -r -g dexnore dexfile

# Install system dependencies and PHP extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl git unzip libzip-dev libpng-dev libonig-dev libxml2-dev procps \
    && docker-php-ext-install $PHP_EXTENSIONS \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && rm -rf /var/lib/apt/lists/*

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
