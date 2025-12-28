# syntax=dexnore/dexfile:0

# Production-ready Ruby Dexfile supporting:
# - Runtimes: MRI (CRuby), JRuby, TruffleRuby, with YJIT optimization
# - Package Managers: Bundler (1.x/2.x/3.x), RubyGems
# - Version Managers: rbenv, RVM, asdf, chruby
# - Frameworks: Rails (all versions), Sinatra, Hanami, Roda, Padrino, Cuba, Grape
# - Asset Pipelines: Sprockets, Propshaft, Webpacker, Shakapacker, Vite Ruby, esbuild
# - App Servers: Puma, Unicorn, Passenger, Pitchfork, Falcon, Iodine, Agoo
# - Web Servers: nginx, Apache, Caddy
# - Deployment Tools: Kamal, Capistrano
# - Monorepos: Workspaces, multi-gem repositories
# - Background Jobs: Sidekiq, Resque, Delayed Job, GoodJob, Solid Queue
# - Databases: PostgreSQL, MySQL, SQLite, Redis

ARG BUILD_IMAGE RUN_IMAGE PORT=3000 RAILS_ENV=production RACK_ENV=production
ARG RUBY_VERSION RUBY_RUNTIME PACKAGE_MANAGER FRAMEWORK_TYPE APP_SERVER
ARG ASSET_PIPELINE WORKSPACE_TYPE WEB_SERVER ENABLE_YJIT=true
ARG NGINX_ROOT="/usr/share/nginx/html"

WORKDIR /home/dexfile/app

# ============================================================================
# RUBY VERSION DETECTION
# ============================================================================
FUNC detect_ruby_version
    # Priority order for Ruby version detection
    # 1. .ruby-version (most common - rbenv, chruby, rvm)
    IF PROC --from=busybox:latest --mount=target=. [ -f ".ruby-version" ]
        ARG RUBY_VERSION=$(cat .ruby-version | tr -d '\n' | sed 's/^ruby-//')
    # 2. .tool-versions (asdf)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".tool-versions" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP 'ruby\s+\K[\d.]+' .tool-versions) && echo "$VERSION"
            ARG RUBY_VERSION=${STDOUT}
        ENDIF
    # 3. Gemfile ruby directive
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Gemfile" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP "^ruby\s+['\"]?\K[\d.]+" Gemfile | head -1) && echo "$VERSION"
            ARG RUBY_VERSION=${STDOUT}
        ENDIF
    # 4. .rvmrc (legacy RVM)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".rvmrc" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP 'ruby-\K[\d.]+' .rvmrc) && echo "$VERSION"
            ARG RUBY_VERSION=${STDOUT}
        ENDIF
    ENDIF
    
    # Set default if not detected
    IF PROC [ -z "${RUBY_VERSION}" ]
        ARG RUBY_VERSION="3.3"
    ENDIF
ENDFUNC

# ============================================================================
# RUBY RUNTIME DETECTION
# ============================================================================
FUNC detect_ruby_runtime
    # Check for JRuby indicators
    IF PROC --from=busybox:latest --mount=target=. [ -f ".jrubyrc" ]
        ARG RUBY_RUNTIME="jruby"
        ARG BUILD_IMAGE="jruby:${RUBY_VERSION}-alpine"
        ARG ENABLE_YJIT="false"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "platforms.*jruby" Gemfile 2>/dev/null
        ARG RUBY_RUNTIME="jruby"
        ARG BUILD_IMAGE="jruby:${RUBY_VERSION}-alpine"
        ARG ENABLE_YJIT="false"
    # Check for TruffleRuby indicators
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "truffleruby" .ruby-version 2>/dev/null
        ARG RUBY_RUNTIME="truffleruby"
        ARG BUILD_IMAGE="ghcr.io/graalvm/truffleruby:latest"
        ARG ENABLE_YJIT="false"
    # Default to MRI (CRuby)
    ELSE
        ARG RUBY_RUNTIME="mri"
        # Use YJIT-enabled builds for Ruby 3.1+
        IF PROC [ "${RUBY_VERSION}" = "3.3" ] || [ "${RUBY_VERSION}" = "3.2" ] || [ "${RUBY_VERSION}" = "3.1" ]
            ARG BUILD_IMAGE="ruby:${RUBY_VERSION}-alpine"
            ARG ENABLE_YJIT="true"
        ELSE
            ARG BUILD_IMAGE="ruby:${RUBY_VERSION}-alpine"
            ARG ENABLE_YJIT="false"
        ENDIF
    ENDIF
ENDFUNC

# ============================================================================
# PACKAGE MANAGER DETECTION
# ============================================================================
FUNC detect_package_manager
    # Check Bundler version from lockfile
    IF PROC --from=busybox:latest --mount=target=. [ -f "Gemfile.lock" ]
        IF PROC --from=busybox:latest --mount=target=. grep -q "BUNDLED WITH" Gemfile.lock
            IF PROC --from=busybox:latest --mount=target=. BUNDLER_VERSION=$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -1 | tr -d ' ') && echo "$BUNDLER_VERSION"
                ARG PACKAGE_MANAGER="bundler-${STDOUT}"
            ELSE
                ARG PACKAGE_MANAGER="bundler-2"
            ENDIF
        ELSE
            ARG PACKAGE_MANAGER="bundler-1"
        ENDIF
    ELSE
        ARG PACKAGE_MANAGER="bundler-2"
    ENDIF
    
    # Check for gems.locked (alternative to Gemfile.lock)
    IF PROC --from=busybox:latest --mount=target=. [ -f "gems.locked" ]
        ARG PACKAGE_MANAGER="bundler-2"
    ENDIF
ENDFUNC

# ============================================================================
# FRAMEWORK DETECTION
# ============================================================================
FUNC detect_framework
    IF PROC --from=busybox:latest --mount=target=. [ ! -f "Gemfile" ]
        RUN echo "ERROR: No Gemfile found" >&2 && exit 1
    ENDIF
    
    # Check for Rails
    IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]rails['\"]" Gemfile || [ -f "config/application.rb" ] && grep -q "Rails::Application" config/application.rb
        ARG FRAMEWORK_TYPE="rails"
        
        # Detect Rails version for specific optimizations
        IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]rails['\"].*['\"]7\." Gemfile
            ARG FRAMEWORK_VERSION="7"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]rails['\"].*['\"]6\." Gemfile
            ARG FRAMEWORK_VERSION="6"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]rails['\"].*['\"]5\." Gemfile
            ARG FRAMEWORK_VERSION="5"
        ENDIF
    # Check for Sinatra
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]sinatra['\"]" Gemfile
        ARG FRAMEWORK_TYPE="sinatra"
    # Check for Hanami
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]hanami['\"]" Gemfile || [ -f "config/app.rb" ]
        ARG FRAMEWORK_TYPE="hanami"
    # Check for Roda
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]roda['\"]" Gemfile
        ARG FRAMEWORK_TYPE="roda"
    # Check for Padrino
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]padrino['\"]" Gemfile || [ -f "config/apps.rb" ]
        ARG FRAMEWORK_TYPE="padrino"
    # Check for Cuba
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]cuba['\"]" Gemfile
        ARG FRAMEWORK_TYPE="cuba"
    # Check for Grape (API framework)
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]grape['\"]" Gemfile
        ARG FRAMEWORK_TYPE="grape"
    # Check for Rack-based apps
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "config.ru" ]
        ARG FRAMEWORK_TYPE="rack"
    ELSE
        ARG FRAMEWORK_TYPE="generic"
    ENDIF
ENDFUNC

# ============================================================================
# ASSET PIPELINE DETECTION
# ============================================================================
FUNC detect_asset_pipeline
    IF PROC [ "${FRAMEWORK_TYPE}" != "rails" ]
        ARG ASSET_PIPELINE="none"
        RETURN
    ENDIF
    
    # Check for Propshaft (Rails 7+ default)
    IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]propshaft['\"]" Gemfile
        ARG ASSET_PIPELINE="propshaft"
    # Check for Sprockets (traditional Rails asset pipeline)
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]sprockets['\"]" Gemfile || grep -q "gem ['\"]sprockets-rails['\"]" Gemfile
        ARG ASSET_PIPELINE="sprockets"
    # Check for Shakapacker (Webpacker successor)
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]shakapacker['\"]" Gemfile || [ -f "config/shakapacker.yml" ]
        ARG ASSET_PIPELINE="shakapacker"
    # Check for Webpacker (legacy)
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]webpacker['\"]" Gemfile || [ -f "config/webpacker.yml" ]
        ARG ASSET_PIPELINE="webpacker"
    # Check for Vite Ruby
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]vite_ruby['\"]" Gemfile || [ -f "vite.config.ts" ] || [ -f "vite.config.js" ]
        ARG ASSET_PIPELINE="vite"
    # Check for jsbundling-rails (esbuild, webpack, rollup)
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]jsbundling-rails['\"]" Gemfile
        IF PROC --from=busybox:latest --mount=target=. [ -f "esbuild.config.js" ] || grep -q "esbuild" package.json 2>/dev/null
            ARG ASSET_PIPELINE="esbuild"
        ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "webpack.config.js" ] || grep -q "webpack" package.json 2>/dev/null
            ARG ASSET_PIPELINE="webpack"
        ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "rollup.config.js" ] || grep -q "rollup" package.json 2>/dev/null
            ARG ASSET_PIPELINE="rollup"
        ELSE
            ARG ASSET_PIPELINE="jsbundling"
        ENDIF
    # Check for cssbundling-rails
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]cssbundling-rails['\"]" Gemfile
        ARG ASSET_PIPELINE="cssbundling"
    # Check for importmap-rails (Rails 7+ default)
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]importmap-rails['\"]" Gemfile
        ARG ASSET_PIPELINE="importmap"
    ELSE
        ARG ASSET_PIPELINE="none"
    ENDIF
ENDFUNC

# ============================================================================
# APP SERVER DETECTION
# ============================================================================
FUNC detect_app_server
    # Check Procfile first (Heroku-style)
    IF PROC --from=busybox:latest --mount=target=. [ -f "Procfile" ]
        IF PROC --from=busybox:latest --mount=target=. grep -q "puma" Procfile
            ARG APP_SERVER="puma"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "unicorn" Procfile
            ARG APP_SERVER="unicorn"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "passenger" Procfile
            ARG APP_SERVER="passenger"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "pitchfork" Procfile
            ARG APP_SERVER="pitchfork"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "falcon" Procfile
            ARG APP_SERVER="falcon"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "iodine" Procfile
            ARG APP_SERVER="iodine"
        ENDIF
    ENDIF
    
    # Check Gemfile if not found in Procfile
    IF PROC [ -z "${APP_SERVER}" ]
        IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]puma['\"]" Gemfile || [ -f "config/puma.rb" ]
            ARG APP_SERVER="puma"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]unicorn['\"]" Gemfile || [ -f "config/unicorn.rb" ]
            ARG APP_SERVER="unicorn"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]passenger['\"]" Gemfile
            ARG APP_SERVER="passenger"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]pitchfork['\"]" Gemfile || [ -f "config/pitchfork.rb" ]
            ARG APP_SERVER="pitchfork"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]falcon['\"]" Gemfile
            ARG APP_SERVER="falcon"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]iodine['\"]" Gemfile
            ARG APP_SERVER="iodine"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gem ['\"]agoo['\"]" Gemfile
            ARG APP_SERVER="agoo"
        ELSE
            # Default to Puma (Rails default since 5.0)
            ARG APP_SERVER="puma"
        ENDIF
    ENDIF
ENDFUNC

# ============================================================================
# WEB SERVER DETECTION
# ============================================================================
FUNC detect_web_server
    # Check for nginx configuration
    IF PROC --from=busybox:latest --mount=target=. [ -f "nginx.conf" ] || [ -f "config/nginx.conf" ]
        ARG WEB_SERVER="nginx"
        ARG RUN_IMAGE="nginx:stable-alpine"
    # Check for Apache configuration
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "apache.conf" ] || [ -f ".htaccess" ] || [ -f "config/apache.conf" ]
        ARG WEB_SERVER="apache"
        ARG RUN_IMAGE="httpd:2.4-alpine"
    # Check for Caddy configuration
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Caddyfile" ] || [ -f "config/Caddyfile" ]
        ARG WEB_SERVER="caddy"
        ARG RUN_IMAGE="caddy:2-alpine"
    ELSE
        ARG WEB_SERVER="none"
    ENDIF
ENDFUNC

# ============================================================================
# WORKSPACE DETECTION
# ============================================================================
FUNC detect_workspace
    # Check for multi-gem repository structures
    IF PROC --from=busybox:latest --mount=target=. [ -f "gems/Gemfile" ] || [ -d "gems" ] && [ $(find gems -name "*.gemspec" | wc -l) -gt 1 ]
        ARG WORKSPACE_TYPE="multi-gem"
    # Check for Rails engines workspace
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -d "engines" ] && [ $(find engines -name "*.gemspec" | wc -l) -gt 0 ]
        ARG WORKSPACE_TYPE="engines"
    # Check for monorepo with multiple apps
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -d "apps" ] && [ $(find apps -name "Gemfile" | wc -l) -gt 1 ]
        ARG WORKSPACE_TYPE="multi-app"
    ELSE
        ARG WORKSPACE_TYPE="single"
    ENDIF
ENDFUNC

# ============================================================================
# RUN DETECTIONS
# ============================================================================
FUNC CALL detect_ruby_version
FUNC CALL detect_ruby_runtime
FUNC CALL detect_package_manager
FUNC CALL detect_framework
FUNC CALL detect_asset_pipeline
FUNC CALL detect_app_server
FUNC CALL detect_web_server
FUNC CALL detect_workspace

# Validate Gemfile exists
IF PROC --from=busybox:latest --mount=target=. [ ! -f "Gemfile" ]
    RUN echo "ERROR: No Gemfile found" >&2 && exit 1
ENDIF

# ============================================================================
# BASE BUILD STAGE
# ============================================================================
FROM ${BUILD_IMAGE} AS base
WORKDIR /home/dexfile/app

# Install system dependencies
RUN set -e; \
    if command -v apk >/dev/null 2>&1; then \
        apk add --no-cache \
            build-base \
            git \
            curl \
            wget \
            bash \
            tzdata \
            shared-mime-info \
            gcompat \
            # Database clients
            postgresql-dev \
            mysql-dev \
            sqlite-dev \
            # Common dependencies
            libxml2-dev \
            libxslt-dev \
            libffi-dev \
            readline-dev \
            yaml-dev \
            zlib-dev \
            openssl-dev \
            # Image processing
            imagemagick \
            vips-dev \
            libwebp-dev \
            libpng-dev \
            libjpeg-turbo-dev \
            giflib-dev \
            # Node.js for asset compilation (if needed)
            nodejs \
            npm \
            yarn; \
    elif command -v apt-get >/dev/null 2>&1; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            build-essential \
            git \
            curl \
            wget \
            bash \
            tzdata \
            libpq-dev \
            libmysqlclient-dev \
            libsqlite3-dev \
            libxml2-dev \
            libxslt1-dev \
            libffi-dev \
            libreadline-dev \
            libyaml-dev \
            zlib1g-dev \
            libssl-dev \
            imagemagick \
            libvips-dev \
            libwebp-dev \
            libpng-dev \
            libjpeg-dev \
            libgif-dev \
            nodejs \
            npm && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    fi

# Set environment variables
ENV RAILS_ENV=production
ENV RACK_ENV=production
ENV BUNDLE_DEPLOYMENT=true
ENV BUNDLE_WITHOUT="development:test"
ENV BUNDLE_JOBS=4
ENV BUNDLE_RETRY=3
ENV BUNDLE_PATH="/usr/local/bundle"
ENV GEM_HOME="/usr/local/bundle"
ENV PATH="${GEM_HOME}/bin:${GEM_HOME}/gems/bin:${PATH}"

# Enable YJIT for Ruby 3.1+ (significant performance boost)
IF PROC [ "${ENABLE_YJIT}" = "true" ]
    ENV RUBY_YJIT_ENABLE=1
ENDIF

# Configure Bundler
RUN gem update --system --no-document && \
    gem install bundler -v '~> 2.0' --no-document && \
    bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle config set --local jobs 4 && \
    bundle config set --local retry 3

# ============================================================================
# DEPENDENCY INSTALLATION STAGE
# ============================================================================
FROM base AS deps

# Copy dependency files
COPY Gemfile Gemfile.lock* gems.rb gems.locked* .ruby-version* /home/dexfile/app/
COPY .bundle/ /home/dexfile/app/.bundle/ 2>/dev/null || true

# Copy gemspecs for gem development
COPY *.gemspec /home/dexfile/app/ 2>/dev/null || true

# Copy workspace gemspecs if multi-gem
COPY gems/*.gemspec /home/dexfile/app/gems/ 2>/dev/null || true
COPY engines/*/. /home/dexfile/app/engines/ 2>/dev/null || true

# Install production dependencies
RUN --mount=type=cache,id=bundle-cache,target=/usr/local/bundle/cache,sharing=locked \
    --mount=type=secret,id=bundle-config,target=/home/dexfile/app/.bundle/config \
    --mount=type=secret,id=rubygems-credentials,target=/root/.gem/credentials \
    set -e; \
    bundle config set --local path '/usr/local/bundle'; \
    bundle config set --local deployment 'true'; \
    bundle config set --local without 'development test'; \
    bundle install --jobs=4 --retry=3 && \
    bundle clean --force && \
    rm -rf /usr/local/bundle/cache/*.gem && \
    find /usr/local/bundle/gems/ -name "*.c" -delete && \
    find /usr/local/bundle/gems/ -name "*.o" -delete

# ============================================================================
# ASSETS PRECOMPILATION STAGE
# ============================================================================
FROM base AS assets

# Copy entire application for asset compilation
COPY . .

# Copy dependencies from deps stage
COPY --from=deps /usr/local/bundle /usr/local/bundle

# Install Node.js dependencies if needed for asset pipeline
RUN --mount=type=cache,id=npm-cache,target=/root/.npm,sharing=locked \
    --mount=type=cache,id=yarn-cache,target=/root/.yarn/cache,sharing=locked \
    set -e; \
    if [ "${ASSET_PIPELINE}" = "shakapacker" ] || \
       [ "${ASSET_PIPELINE}" = "webpacker" ] || \
       [ "${ASSET_PIPELINE}" = "vite" ] || \
       [ "${ASSET_PIPELINE}" = "esbuild" ] || \
       [ "${ASSET_PIPELINE}" = "webpack" ] || \
       [ "${ASSET_PIPELINE}" = "rollup" ]; then \
        if [ -f "package.json" ]; then \
            if [ -f "yarn.lock" ]; then \
                yarn install --frozen-lockfile --production; \
            elif [ -f "package-lock.json" ]; then \
                npm ci --omit=dev; \
            else \
                npm install --production; \
            fi; \
        fi; \
    fi

# Precompile assets based on framework
RUN --mount=type=cache,id=rails-cache,target=/home/dexfile/app/tmp/cache,sharing=locked \
    --mount=type=secret,id=master-key,target=/home/dexfile/app/config/master.key \
    --mount=type=secret,id=credentials,target=/home/dexfile/app/config/credentials.yml.enc \
    set -e; \
    if [ "${FRAMEWORK_TYPE}" = "rails" ]; then \
        # Set dummy secrets for asset compilation
        export SECRET_KEY_BASE=${SECRET_KEY_BASE:-$(bundle exec rake secret 2>/dev/null || openssl rand -hex 64)}; \
        # Precompile assets
        if [ -f "bin/rails" ]; then \
            bundle exec rails assets:precompile 2>/dev/null || echo "No assets to precompile"; \
        elif [ -f "Rakefile" ]; then \
            bundle exec rake assets:precompile 2>/dev/null || echo "No assets to precompile"; \
        fi; \
        # Clean up build artifacts
        rm -rf node_modules tmp/cache vendor/assets lib/assets; \
    fi

# ============================================================================
# RUNTIME BASE STAGE
# ============================================================================
FROM ${RUN_IMAGE} AS app

# Create non-root user
RUN set -e; \
    if command -v addgroup >/dev/null 2>&1; then \
        addgroup -S dexnore 2>/dev/null || true; \
        adduser -S -D -H -h /home/dexfile/app -s /sbin/nologin -G dexnore dexfile 2>/dev/null || true; \
    elif command -v groupadd >/dev/null 2>&1; then \
        groupadd -r dexnore 2>/dev/null || true; \
        useradd -r -g dexnore -d /home/dexfile/app -s /sbin/nologin dexfile 2>/dev/null || true; \
    fi && \
    mkdir -p /home/dexfile/app && \
    chown -R dexfile:dexnore /home/dexfile/app 2>/dev/null || chown -R 1000:1000 /home/dexfile/app

WORKDIR /home/dexfile/app

ENV RAILS_ENV=production
ENV RACK_ENV=production
ENV PORT=${PORT}
EXPOSE ${PORT}

# ============================================================================
# PRODUCTION STAGE
# ============================================================================
FROM app AS prod

# Handle static file serving with web servers
IF PROC [ -n "${WEB_SERVER}" ] && [ "${WEB_SERVER}" != "none" ]
    # Copy web server config
    IF PROC [ "${WEB_SERVER}" = "nginx" ]
        COPY --chown=root:root nginx.conf /etc/nginx/conf.d/default.conf 2>/dev/null || \
             COPY --chown=root:root config/nginx.conf /etc/nginx/conf.d/default.conf 2>/dev/null || true
    ELSE IF PROC [ "${WEB_SERVER}" = "apache" ]
        COPY --chown=root:root apache.conf /usr/local/apache2/conf/httpd.conf 2>/dev/null || \
             COPY --chown=root:root config/apache.conf /usr/local/apache2/conf/httpd.conf 2>/dev/null || true
    ELSE IF PROC [ "${WEB_SERVER}" = "caddy" ]
        COPY --chown=root:root Caddyfile /etc/caddy/Caddyfile 2>/dev/null || \
             COPY --chown=root:root config/Caddyfile /etc/caddy/Caddyfile 2>/dev/null || true
    ENDIF
    
    # Copy precompiled assets
    COPY --chown=nginx:nginx --from=assets /home/dexfile/app/public ${NGINX_ROOT}/ 2>/dev/null || true
    
    # Set proper permissions
    RUN chown -R nginx:nginx ${NGINX_ROOT} && chmod -R 755 ${NGINX_ROOT}
    
    # Start web server
    IF PROC [ "${WEB_SERVER}" = "nginx" ]
        CMD ["nginx", "-g", "daemon off;"]
    ELSE IF PROC [ "${WEB_SERVER}" = "apache" ]
        CMD ["httpd-foreground"]
    ELSE
        CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]
    ENDIF

# Handle Ruby application runtime
ELSE
    # Install minimal runtime dependencies
    RUN set -e; \
        if command -v apk >/dev/null 2>&1; then \
            apk add --no-cache \
                tzdata \
                shared-mime-info \
                gcompat \
                postgresql-libs \
                mysql-client \
                sqlite-libs \
                libxml2 \
                libxslt \
                libffi \
                readline \
                yaml \
                zlib \
                openssl \
                vips \
                libwebp \
                libpng \
                libjpeg-turbo \
                giflib \
                curl \
                bash; \
        elif command -v apt-get >/dev/null 2>&1; then \
            apt-get update && \
            apt-get install -y --no-install-recommends \
                tzdata \
                libpq5 \
                libmysqlclient21 \
                libsqlite3-0 \
                libxml2 \
                libxslt1.1 \
                libffi7 \
                libreadline8 \
                libyaml-0-2 \
                zlib1g \
                libssl1.1 \
                libvips42 \
                libwebp6 \
                libpng16-16 \
                libjpeg62-turbo \
                libgif7 \
                curl \
                bash && \
            apt-get clean && \
            rm -rf /var/lib/apt/lists/*; \
        fi
    
    # Set environment for production
    ENV RAILS_ENV=production
    ENV RACK_ENV=production
    ENV RAILS_SERVE_STATIC_FILES=true
    ENV RAILS_LOG_TO_STDOUT=true
    ENV BUNDLE_PATH="/usr/local/bundle"
    ENV GEM_HOME="/usr/local/bundle"
    ENV PATH="${GEM_HOME}/bin:${GEM_HOME}/gems/bin:${PATH}"
    
    # Enable YJIT in production
    IF PROC [ "${ENABLE_YJIT}" = "true" ]
        ENV RUBY_YJIT_ENABLE=1
    ENDIF
    
    # Copy Ruby and gems
    COPY --from=deps /usr/local/bundle /usr/local/bundle
    
    # Copy application files
    COPY --chown=dexfile:dexnore . .
    
    # Copy precompiled assets if Rails
    IF PROC [ "${FRAMEWORK_TYPE}" = "rails" ]
        COPY --chown=dexfile:dexnore --from=assets /home/dexfile/app/public/assets ./public/assets 2>/dev/null || true
        COPY --chown=dexfile:dexnore --from=assets /home/dexfile/app/public/packs ./public/packs 2>/dev/null || true
        COPY --chown=dexfile:dexnore --from=assets /home/dexfile/app/public/vite ./public/vite 2>/dev/null || true
    ENDIF
    
    # Create necessary directories
    RUN mkdir -p tmp/pids tmp/cache tmp/sockets log && \
        chown -R dexfile:dexnore tmp log
    
    USER dexfile:dexnore
    
    # Framework-specific health checks
    IF PROC [ "${FRAMEWORK_TYPE}" = "rails" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
            CMD curl -f http://127.0.0.1:${PORT}/up 2>/dev/null || \
                curl -f http://127.0.0.1:${PORT}/ || exit 1
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "sinatra" ] || [ "${FRAMEWORK_TYPE}" = "rack" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
            CMD curl -f http://127.0.0.1:${PORT}/health 2>/dev/null || \
                curl -f http://127.0.0.1:${PORT}/ || exit 1
    ENDIF
    
    # Set entrypoint based on app server
    IF PROC [ "${APP_SERVER}" = "puma" ]
        # Puma with config file or defaults
        IF PROC --from=busybox:latest --mount=target=. [ -f "config/puma.rb" ]
            CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
        ELSE
            CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:${PORT}", "-e", "production"]
        ENDIF
    ELSE IF PROC [ "${APP_SERVER}" = "unicorn" ]
        IF PROC --from=busybox:latest --mount=target=. [ -f "config/unicorn.rb" ]
            CMD ["bundle", "exec", "unicorn", "-c", "config/unicorn.rb"]
        ELSE
            CMD ["bundle", "exec", "unicorn", "-p", "${PORT}", "-E", "production"]
        ENDIF
    ELSE IF PROC [ "${APP_SERVER}" = "passenger" ]
        CMD ["bundle", "exec", "passenger", "start", "--port", "${PORT}", "--environment", "production"]
    ELSE IF PROC [ "${APP_SERVER}" = "pitchfork" ]
        IF PROC --from=busybox:latest --mount=target=. [ -f "config/pitchfork.rb" ]
            CMD ["bundle", "exec", "pitchfork", "-c", "config/pitchfork.rb"]
        ELSE
            CMD ["bundle", "exec", "pitchfork", "-p", "${PORT}"]
        ENDIF
    ELSE IF PROC [ "${APP_SERVER}" = "falcon" ]
        CMD ["bundle", "exec", "falcon", "serve", "--port", "${PORT}", "--environment", "production"]
    ELSE IF PROC [ "${APP_SERVER}" = "iodine" ]
        CMD ["bundle", "exec", "iodine", "-p", "${PORT}", "-e", "production"]
    ELSE IF PROC [ "${APP_SERVER}" = "agoo" ]
        CMD ["bundle", "exec", "rackup", "-s", "agoo", "-p", "${PORT}", "-E", "production"]
    ELSE
        # Fallback to rackup for Rack apps
        IF PROC --from=busybox:latest --mount=target=. [ -f "config.ru" ]
            CMD ["bundle", "exec", "rackup", "-p", "${PORT}", "-E", "production"]
        ELSE
            # Rails default
            CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "${PORT}"]
        ENDIF
    ENDIF
ENDIF

# ============================================================================
# RELEASE STAGE
# ============================================================================
FROM prod AS release

# Metadata labels
LABEL maintainer="@dexnore/dexfile"
LABEL org.opencontainers.image.vendor="Dexnore"
LABEL org.opencontainers.image.title="Ruby Application"
LABEL org.opencontainers.image.description="Production Ruby application supporting multiple runtimes, frameworks, and app servers"
LABEL org.opencontainers.image.authors="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

# Dynamic labels based on detection
LABEL app.runtime="${RUBY_RUNTIME}"
LABEL app.ruby-version="${RUBY_VERSION}"
LABEL app.framework="${FRAMEWORK_TYPE}"
LABEL app.app-server="${APP_SERVER}"
LABEL app.asset-pipeline="${ASSET_PIPELINE}"
LABEL app.workspace="${WORKSPACE_TYPE}"
LABEL app.yjit-enabled="${ENABLE_YJIT}"
LABEL security.non-root="true"

FROM release