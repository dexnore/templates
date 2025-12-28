# syntax=docker/dockerfile:1.7

###############################################################################
# Base runtime: Apache + mod_php
###############################################################################
FROM php:8.3-apache-bookworm AS php-apache-base

ARG IPE_VERSION=1.6.0

###############################################################################
# System deps + PHP extensions (deterministic)
###############################################################################
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl; \
    \
    curl -fsSL \
      https://github.com/mlocati/docker-php-extension-installer/releases/download/${IPE_VERSION}/install-php-extensions \
      -o /usr/local/bin/install-php-extensions; \
    chmod +x /usr/local/bin/install-php-extensions; \
    \
    install-php-extensions \
        opcache \
        bcmath \
        exif \
        intl \
        gd \
        zip \
        pdo_mysql \
        pdo_pgsql \
        redis \
        pcntl \
        apcu; \
    \
    rm /usr/local/bin/install-php-extensions; \
    apt-get purge -y curl; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*

###############################################################################
# PHP configuration (production)
###############################################################################
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY <<'EOF' $PHP_INI_DIR/conf.d/zz-production.ini
expose_php=0

memory_limit=512M
max_execution_time=60
upload_max_filesize=50M
post_max_size=50M

realpath_cache_size=4096K
realpath_cache_ttl=600

opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0

apc.enable_cli=1
EOF

###############################################################################
# Apache hardening & modules
###############################################################################
RUN set -eux; \
    a2enmod rewrite headers expires deflate http2; \
    a2dismod status autoindex -f

COPY <<'EOF' /etc/apache2/conf-available/security-hardening.conf
ServerTokens Prod
ServerSignature Off
TraceEnable Off

Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
EOF

RUN a2enconf security-hardening

###############################################################################
# Virtual host
###############################################################################
COPY <<'EOF' /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ServerName _
    DocumentRoot /var/www/html/public

    <Directory /var/www/html/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler application/x-httpd-php
    </FilesMatch>

    ErrorLog /dev/stderr
    CustomLog /dev/stdout combined
</VirtualHost>
EOF

###############################################################################
# Builder (Composer with BuildKit cache)
###############################################################################
FROM php-apache-base AS builder

WORKDIR /app
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock ./

RUN --mount=type=cache,target=/tmp/cache/composer \
    COMPOSER_CACHE_DIR=/tmp/cache/composer \
    composer validate --no-check-publish && \
    composer install \
      --no-dev \
      --no-scripts \
      --no-autoloader \
      --prefer-dist \
      --no-interaction \
      --no-progress

COPY . .
RUN composer dump-autoload --optimize --classmap-authoritative

###############################################################################
# Final runtime
###############################################################################
FROM php-apache-base AS final

WORKDIR /var/www/html
COPY --from=builder --chown=www-data:www-data /app /var/www/html

RUN set -eux; \
    find /var/www/html -type d -exec chmod 755 {} \; ; \
    find /var/www/html -type f -exec chmod 644 {} \;

###############################################################################
# Runtime metadata
###############################################################################
EXPOSE 80
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1/ || exit 1

CMD ["apache2-foreground"]
