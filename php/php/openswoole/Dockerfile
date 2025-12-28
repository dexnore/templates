# syntax=docker/dockerfile:1.7

############################
# Stage 1: Base Runtime
############################
FROM php:8.3-cli-alpine AS base

ENV APP_ENV=production \
    PHP_INI_DIR=/usr/local/etc/php \
    PHP_OUTPUT_BUFFERING=Off

# Minimal runtime deps (OpenSwoole needs libstdc++ for its C++ core)
RUN apk add --no-cache \
        bash \
        ca-certificates \
        tzdata \
        curl \
        libstdc++ \
    && update-ca-certificates

# PHP Extension Installer
ARG IPE_VERSION=1.6.0
ADD https://github.com/mlocati/docker-php-extension-installer/releases/download/${IPE_VERSION}/install-php-extensions /usr/local/bin/install-php-extensions

RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions \
        opcache pdo_mysql pdo_pgsql redis zip gd intl bcmath exif pcntl sockets openswoole \
    && rm -f /usr/local/bin/install-php-extensions

# PHP Production Config (Optimized for CLI Long-running)
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY <<'EOF' $PHP_INI_DIR/conf.d/zz-openswoole.ini
expose_php = 0
memory_limit = 512M
max_execution_time = 0
output_buffering = Off
variables_order = "EGPCS"

; Opcache CLI is mandatory for persistent processes
opcache.enable_cli = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 0

; OpenSwoole Specifics
openswoole.use_shortname = Off
pcntl.async_signals = 1
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
    composer install --no-dev --no-interaction --no-scripts --prefer-dist --no-autoloader

COPY . .
RUN composer dump-autoload --optimize --classmap-authoritative

############################
# Stage 3: Final Runtime
############################
FROM base AS final
WORKDIR /app

# Non-root runtime user
RUN addgroup -g 1000 app && adduser -D -u 1000 -G app app

# Copy code with ownership
COPY --from=builder --chown=app:app /app /app

# Ensure we have the server script ready
COPY --chown=app:app <<'EOF' /app/server.php
<?php
use OpenSwoole\Http\Server;
use OpenSwoole\Http\Request;
use OpenSwoole\Http\Response;

// Use CPU count for optimal worker distribution
$server = new Server('0.0.0.0', 9000);

$server->set([
    'worker_num'      => swoole_cpu_num(),
    'enable_coroutine' => true,
    'max_coroutine'    => 100000,
    'max_request'      => 1000,
    'reload_async'     => true,
    'max_wait_time'    => 60,
    'enable_reuse_port' => true,
    'hook_flags'       => SWOOLE_HOOK_ALL, 
]);

$server->on('request', function (Request $req, Response $res) {
    if ($req->server['request_uri'] === '/health') {
        $res->status(200);
        $res->end('ok');
        return;
    }

    $res->header('Content-Type', 'application/json');
    $res->end(json_encode(['status' => 'ok', 'engine' => 'openswoole']));
});

$server->start();
EOF

USER app
EXPOSE 9000

# Reliable healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://127.0.0.1:9000/health || exit 1

STOPSIGNAL SIGTERM

CMD ["php", "/app/server.php"]