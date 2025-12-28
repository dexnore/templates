# syntax=docker/dockerfile:1.7

############################
# Stage 1: Base Runtime
############################
FROM litespeedtech/openlitespeed:1.7-lsphp83 AS base

ENV APP_ENV=production \
    PHP_VERSION=8.3 \
    LS_PATH=/usr/local/lsws

# Minimal runtime tooling only
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
    && rm -rf /var/lib/apt/lists/*

############################
# PHP Extensions (Pinned)
############################
RUN /usr/local/lsws/lsphp83/bin/pecl install redis-6.0.2 \
    && echo "extension=redis.so" \
        > /usr/local/lsws/lsphp83/etc/php/8.3/conf.d/20-redis.ini

############################
# PHP Production Config
############################
COPY <<'EOF' /usr/local/lsws/lsphp83/etc/php/8.3/conf.d/99-production.ini
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

# CLI convenience only for build stage
RUN ln -sf /usr/local/lsws/lsphp83/bin/lsphp /usr/local/bin/php

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
WORKDIR /var/www/html

COPY --from=builder /app /var/www/html

############################
# OpenLiteSpeed Configuration
############################
COPY <<'EOF' /usr/local/lsws/conf/httpd_config.conf
serverName openlitespeed
user nobody
group nogroup
priority 0
autoRestart 1

listener Default {
  address *:80
  secure 0
}

virtualhost Default {
  vhRoot /var/www/html
  configFile /usr/local/lsws/conf/vhosts/Default/vhconf.conf
}
EOF

COPY <<'EOF' /usr/local/lsws/conf/vhosts/Default/vhconf.conf
docRoot $VH_ROOT/public
vhDomain $VH_NAME
vhAliases *

index {
  indexFiles index.php, index.html
}

scripthandler {
  add lsapi:lsphp83 php
}

rewrite {
  enable 1
  rules <<<END
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule ^(.*)$ /index.php [L,QSA]
  END
}
EOF

############################
# Permissions
############################
RUN chown -R nobody:nogroup \
        /var/www/html \
        /usr/local/lsws/logs \
        /usr/local/lsws/tmp

############################
# Runtime
############################
EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1/health || exit 1

STOPSIGNAL SIGTERM

CMD ["/usr/local/lsws/bin/openlitespeed", "-n"]
