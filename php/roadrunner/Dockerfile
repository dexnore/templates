# syntax=docker/dockerfile:1.7

############################
# Stage 1: Base PHP runtime
############################
FROM php:8.3-cli-alpine3.20 AS base

ENV APP_ENV=production \
    PHP_INI_DIR=/usr/local/etc/php \
    # Ensure PHP doesn't buffer output, allowing RR to capture logs in real-time
    PHP_OUTPUT_BUFFERING=Off

# System deps: wget is used for healthcheck to avoid heavy curl in final image
RUN apk add --no-cache \
        ca-certificates \
        tzdata \
        linux-headers \
        bash \
    && update-ca-certificates

# PHP extension installer (pinned version)
ARG IPE_VERSION=1.6.0
ADD https://github.com/mlocati/docker-php-extension-installer/releases/download/${IPE_VERSION}/install-php-extensions \
    /usr/local/bin/install-php-extensions
RUN chmod +x /usr/local/bin/install-php-extensions

# Core extensions for high-performance RoadRunner execution
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
        sockets \
        protobuf \
        grpc && \
    rm /usr/local/bin/install-php-extensions

############################
# Stage 2: PHP production config
############################
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY <<'EOF' $PHP_INI_DIR/conf.d/zz-production.ini
expose_php = 0
memory_limit = 512M
# RoadRunner handles timeouts; setting this to 0 prevents PHP from killing the worker prematurely
max_execution_time = 0
realpath_cache_size = 4096K
realpath_cache_ttl = 600

# Critical for RoadRunner: Code is loaded into memory once at startup
opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 0
EOF

############################
# Stage 3: Builder (Composer)
############################
FROM base AS builder
WORKDIR /app

COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock ./

# Use BuildKit cache mount for composer downloads
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
# Stage 4: RoadRunner Binary
############################
FROM ghcr.io/roadrunner-server/roadrunner:2024.3.3 AS roadrunner_bin

############################
# Stage 5: Final runtime image
############################
FROM base AS final
WORKDIR /app

# Non-root user with deterministic UID/GID
RUN addgroup -g 1000 app && adduser -D -u 1000 -G app app

# Copy RR binary and application code
COPY --from=roadrunner_bin /usr/bin/rr /usr/local/bin/rr
COPY --from=builder --chown=app:app /app /app

# Ensure correct permissions for RoadRunner cache/temp files
USER app

############################
# RoadRunner Configuration
############################
COPY --after-user <<'EOF' /app/.rr.yaml
version: "3"

server:
  command: "php worker.php"
  relay: pipes

http:
  address: 0.0.0.0:8080
  max_request_size: 50
  middleware: ["gzip", "headers"]
  pool:
    num_workers: 4 # Adjust based on CPU cores
    max_jobs: 0    # Workers stay alive indefinitely unless they fail
    allocate_timeout: 60s
    destroy_timeout: 60s
    # Supervisor: Safeguard against memory leaks in long-lived PHP workers
    supervisor:
      watch_tick: 1s
      max_worker_memory: 128 # Graceful restart if worker exceeds 128MB
  headers:
    response:
      X-Frame-Options: "SAMEORIGIN"
      X-Content-Type-Options: "nosniff"

logs:
  mode: production
  level: warn
  encoding: json
  output: stdout
  err_output: stderr

# Useful for Prometheus monitoring
metrics:
  address: 0.0.0.0:2112

# Readiness/Liveness probe endpoint
status:
  address: 0.0.0.0:2114
EOF

############################
# Metadata & Entrypoint
############################
EXPOSE 8080 2112 2114
STOPSIGNAL SIGTERM

# Use wget (builtin to Alpine) instead of curl to keep image slim
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:2114/health || exit 1

ENTRYPOINT ["/usr/local/bin/rr"]
CMD ["serve", "-c", "/app/.rr.yaml"]