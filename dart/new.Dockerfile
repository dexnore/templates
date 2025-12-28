# syntax=dexnore/dexfile:0

# Production-ready Dart Dexfile supporting:
# - Runtimes: Dart VM (JIT), AOT Compiled Native, dart2js (Web), dart2wasm
# - Frameworks: Shelf, Dart Frog, Serverpod, Jaspr, Dartness, Alfred, Conduit
# - Package Managers: pub, dart pub, flutter pub
# - Monorepo Tools: Melos, Pub Workspaces
# - Web Servers: nginx, Caddy, Apache (for static dart2js output)
# - Build Modes: debug, profile, release, AOT compilation
# - Platforms: Server, Web (JS/Wasm), Native

ARG BUILD_IMAGE RUN_IMAGE PORT=8080 DART_ENV=production
ARG DART_VERSION DART_RUNTIME FRAMEWORK_TYPE BUILD_MODE=release
ARG PACKAGE_MANAGER WORKSPACE_TYPE WEB_SERVER ENABLE_AOT=true
ARG COMPILE_TARGET="exe" NGINX_ROOT="/usr/share/nginx/html"

WORKDIR /home/dexfile/app

# ============================================================================
# DART VERSION DETECTION
# ============================================================================
FUNC detect_dart_version
    # Priority order for Dart version detection
    # 1. .dart-version (custom convention)
    IF PROC --from=busybox:latest --mount=target=. [ -f ".dart-version" ]
        ARG DART_VERSION=$(cat .dart-version | tr -d '\n' | sed 's/^dart-//')
    # 2. .tool-versions (asdf)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".tool-versions" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP 'dart\s+\K[\d.]+' .tool-versions) && echo "$VERSION"
            ARG DART_VERSION=${STDOUT}
        ENDIF
    # 3. pubspec.yaml environment.sdk constraint
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "pubspec.yaml" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -A 1 "environment:" pubspec.yaml | grep "sdk:" | grep -oP '[>=^~]*\K[\d.]+' | head -1) && echo "$VERSION"
            ARG DART_VERSION=${STDOUT}
        ENDIF
    # 4. flutter/dart-sdk-version (Flutter projects)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".flutter-version" ]
        # Use latest stable Dart for Flutter projects
        ARG DART_VERSION="stable"
    ENDIF
    
    # Set default if not detected
    IF PROC [ -z "${DART_VERSION}" ]
        ARG DART_VERSION="stable"
    ENDIF
ENDFUNC

# ============================================================================
# DART RUNTIME DETECTION
# ============================================================================
FUNC detect_dart_runtime
    # Check for web compilation targets (dart2js, dart2wasm)
    IF PROC --from=busybox:latest --mount=target=. [ -f "web/index.html" ] || [ -d "web" ]
        # Check for wasm configuration
        IF PROC --from=busybox:latest --mount=target=. grep -q "wasm" pubspec.yaml 2>/dev/null || grep -q "dart2wasm" pubspec.yaml 2>/dev/null
            ARG DART_RUNTIME="dart2wasm"
            ARG COMPILE_TARGET="wasm"
            ARG ENABLE_AOT="false"
        ELSE
            ARG DART_RUNTIME="dart2js"
            ARG COMPILE_TARGET="js"
            ARG ENABLE_AOT="false"
        ENDIF
    # Check for explicit AOT compilation request
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Dockerfile.aot" ] || grep -q "aot" pubspec.yaml 2>/dev/null
        ARG DART_RUNTIME="aot"
        ARG COMPILE_TARGET="aot-snapshot"
        ARG ENABLE_AOT="true"
    # Check for native compilation
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "dart compile exe" pubspec.yaml 2>/dev/null
        ARG DART_RUNTIME="native"
        ARG COMPILE_TARGET="exe"
        ARG ENABLE_AOT="true"
    # Default to JIT (Dart VM)
    ELSE
        ARG DART_RUNTIME="jit"
        ARG COMPILE_TARGET="kernel"
        ARG ENABLE_AOT="false"
    ENDIF
    
    # Set build image based on runtime
    IF PROC [ "${DART_VERSION}" = "stable" ] || [ "${DART_VERSION}" = "beta" ] || [ "${DART_VERSION}" = "dev" ]
        ARG BUILD_IMAGE="dart:${DART_VERSION}"
    ELSE
        ARG BUILD_IMAGE="dart:${DART_VERSION}"
    ENDIF
ENDFUNC

# ============================================================================
# PACKAGE MANAGER DETECTION
# ============================================================================
FUNC detect_package_manager
    # Check for Melos (monorepo tool)
    IF PROC --from=busybox:latest --mount=target=. [ -f "melos.yaml" ]
        ARG PACKAGE_MANAGER="melos"
        ARG WORKSPACE_TYPE="melos"
    # Check for Pub Workspaces
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "workspace:" pubspec.yaml 2>/dev/null
        ARG PACKAGE_MANAGER="pub-workspaces"
        ARG WORKSPACE_TYPE="pub-workspaces"
    # Check for Flutter project
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "flutter:" pubspec.yaml 2>/dev/null || [ -f ".flutter-version" ]
        ARG PACKAGE_MANAGER="flutter-pub"
    # Standard Dart pub
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "pubspec.yaml" ]
        ARG PACKAGE_MANAGER="pub"
    ELSE
        RUN echo "ERROR: No pubspec.yaml found" >&2 && exit 1
    ENDIF
ENDFUNC

# ============================================================================
# FRAMEWORK DETECTION
# ============================================================================
FUNC detect_framework
    IF PROC --from=busybox:latest --mount=target=. [ ! -f "pubspec.yaml" ]
        RUN echo "ERROR: No pubspec.yaml found" >&2 && exit 1
    ENDIF
    
    # Check for Dart Frog
    IF PROC --from=busybox:latest --mount=target=. grep -q "dart_frog" pubspec.yaml || [ -f "routes/index.dart" ] || [ -d "routes" ]
        ARG FRAMEWORK_TYPE="dart_frog"
    # Check for Serverpod
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "serverpod" pubspec.yaml || [ -f "config/generator.yaml" ]
        ARG FRAMEWORK_TYPE="serverpod"
    # Check for Jaspr (Flutter for web)
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "jaspr" pubspec.yaml
        ARG FRAMEWORK_TYPE="jaspr"
        ARG DART_RUNTIME="dart2js"
    # Check for Shelf
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "shelf" pubspec.yaml
        ARG FRAMEWORK_TYPE="shelf"
    # Check for Dartness (Express-like)
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "dartness" pubspec.yaml
        ARG FRAMEWORK_TYPE="dartness"
    # Check for Alfred
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "alfred" pubspec.yaml
        ARG FRAMEWORK_TYPE="alfred"
    # Check for Conduit (Aqueduct successor)
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "conduit" pubspec.yaml || [ -f "config.yaml" ]
        ARG FRAMEWORK_TYPE="conduit"
    # Check for pure web app (dart2js/wasm)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -d "web" ] && [ -f "web/index.html" ]
        ARG FRAMEWORK_TYPE="web"
        IF PROC --from=busybox:latest --mount=target=. grep -q "wasm" pubspec.yaml 2>/dev/null
            ARG DART_RUNTIME="dart2wasm"
        ELSE
            ARG DART_RUNTIME="dart2js"
        ENDIF
    # Check for CLI application
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "bin/main.dart" ] || [ -d "bin" ]
        ARG FRAMEWORK_TYPE="cli"
    ELSE
        ARG FRAMEWORK_TYPE="generic"
    ENDIF
ENDFUNC

# ============================================================================
# BUILD MODE DETECTION
# ============================================================================
FUNC detect_build_mode
    # Check for explicit build mode in environment or config
    IF PROC --from=busybox:latest --mount=target=. grep -q "build_mode.*profile" pubspec.yaml 2>/dev/null
        ARG BUILD_MODE="profile"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "build_mode.*debug" pubspec.yaml 2>/dev/null
        ARG BUILD_MODE="debug"
        ARG ENABLE_AOT="false"
    ELSE
        ARG BUILD_MODE="release"
    ENDIF
ENDFUNC

# ============================================================================
# WEB SERVER DETECTION (for static dart2js/wasm output)
# ============================================================================
FUNC detect_web_server
    # Only relevant for web compilation targets
    IF PROC [ "${DART_RUNTIME}" = "dart2js" ] || [ "${DART_RUNTIME}" = "dart2wasm" ]
        IF PROC --from=busybox:latest --mount=target=. [ -f "nginx.conf" ] || [ -f "config/nginx.conf" ]
            ARG WEB_SERVER="nginx"
            ARG RUN_IMAGE="nginx:stable-alpine"
        ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Caddyfile" ] || [ -f "config/Caddyfile" ]
            ARG WEB_SERVER="caddy"
            ARG RUN_IMAGE="caddy:2-alpine"
        ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "apache.conf" ] || [ -f ".htaccess" ]
            ARG WEB_SERVER="apache"
            ARG RUN_IMAGE="httpd:2.4-alpine"
        ELSE
            ARG WEB_SERVER="nginx"
            ARG RUN_IMAGE="nginx:stable-alpine"
        ENDIF
    ELSE
        ARG WEB_SERVER="none"
    ENDIF
ENDFUNC

# ============================================================================
# WORKSPACE DETECTION
# ============================================================================
FUNC detect_workspace
    IF PROC [ -n "${WORKSPACE_TYPE}" ]
        RETURN
    ENDIF
    
    # Check for Melos workspace
    IF PROC --from=busybox:latest --mount=target=. [ -f "melos.yaml" ]
        ARG WORKSPACE_TYPE="melos"
    # Check for Pub Workspaces
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "workspace:" pubspec.yaml 2>/dev/null
        ARG WORKSPACE_TYPE="pub-workspaces"
    # Check for multiple packages
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -d "packages" ] && [ $(find packages -name "pubspec.yaml" | wc -l) -gt 1 ]
        ARG WORKSPACE_TYPE="multi-package"
    ELSE
        ARG WORKSPACE_TYPE="single"
    ENDIF
ENDFUNC

# ============================================================================
# RUN DETECTIONS
# ============================================================================
FUNC CALL detect_dart_version
FUNC CALL detect_dart_runtime
FUNC CALL detect_package_manager
FUNC CALL detect_framework
FUNC CALL detect_build_mode
FUNC CALL detect_web_server
FUNC CALL detect_workspace

# Validate pubspec.yaml exists
IF PROC --from=busybox:latest --mount=target=. [ ! -f "pubspec.yaml" ]
    RUN echo "ERROR: No pubspec.yaml found" >&2 && exit 1
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
            ca-certificates \
            git \
            curl \
            wget \
            bash \
            unzip \
            openssh-client \
            build-base \
            # For native compilation
            gcc \
            g++ \
            make; \
    elif command -v apt-get >/dev/null 2>&1; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            ca-certificates \
            git \
            curl \
            wget \
            bash \
            unzip \
            openssh-client \
            build-essential \
            gcc \
            g++ \
            make && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    fi

# Set Dart environment variables
ENV DART_ENV=production
ENV PUB_CACHE=/home/dexfile/.pub-cache
ENV PATH="${PATH}:/home/dexfile/.pub-cache/bin"

# Configure pub to use system cache
RUN dart --version && \
    dart pub --version

# ============================================================================
# DEPENDENCY INSTALLATION STAGE
# ============================================================================
FROM base AS deps

# Copy dependency files
COPY pubspec.yaml pubspec.lock* analysis_options.yaml* /home/dexfile/app/
COPY .dart_tool/ /home/dexfile/app/.dart_tool/ 2>/dev/null || true

# Copy workspace files if needed
IF PROC [ "${WORKSPACE_TYPE}" = "melos" ]
    COPY melos.yaml /home/dexfile/app/
    COPY packages/*/pubspec.yaml /home/dexfile/app/packages/ 2>/dev/null || true
ELSE IF PROC [ "${WORKSPACE_TYPE}" = "pub-workspaces" ]
    COPY packages/*/pubspec.yaml /home/dexfile/app/packages/ 2>/dev/null || true
ENDIF

# Install Melos if needed
RUN --mount=type=cache,id=pub-cache,target=/home/dexfile/.pub-cache,sharing=locked \
    set -e; \
    if [ "${PACKAGE_MANAGER}" = "melos" ]; then \
        dart pub global activate melos; \
    fi

# Install dependencies
RUN --mount=type=cache,id=pub-cache,target=/home/dexfile/.pub-cache,sharing=locked \
    --mount=type=secret,id=pub-credentials,target=/home/dexfile/.pub-cache/credentials.json \
    set -e; \
    if [ "${PACKAGE_MANAGER}" = "melos" ]; then \
        melos bootstrap --no-private; \
    elif [ "${PACKAGE_MANAGER}" = "pub-workspaces" ]; then \
        dart pub get --no-precompile; \
    elif [ "${PACKAGE_MANAGER}" = "flutter-pub" ]; then \
        # Flutter projects need Flutter SDK
        echo "Flutter projects require Flutter SDK - using dart pub as fallback"; \
        dart pub get --no-precompile; \
    else \
        dart pub get --no-precompile; \
    fi

# ============================================================================
# BUILDER STAGE (Compile/Build Application)
# ============================================================================
FROM base AS builder

# Copy all source files
COPY . .

# Copy dependencies from deps stage
COPY --from=deps /home/dexfile/.pub-cache /home/dexfile/.pub-cache
COPY --from=deps /home/dexfile/app/.dart_tool /home/dexfile/app/.dart_tool

# Run build_runner if needed (code generation)
RUN --mount=type=cache,id=pub-cache,target=/home/dexfile/.pub-cache,sharing=locked \
    set -e; \
    if grep -q "build_runner" pubspec.yaml 2>/dev/null; then \
        dart run build_runner build --delete-conflicting-outputs --release; \
    fi

# Compile based on runtime target
RUN --mount=type=cache,id=dart-build-cache,target=/home/dexfile/app/.dart_tool,sharing=locked \
    set -e; \
    mkdir -p /home/dexfile/app/build; \
    \
    # AOT Native Executable (fastest startup, smallest size)
    if [ "${DART_RUNTIME}" = "native" ] || [ "${DART_RUNTIME}" = "aot" ]; then \
        if [ "${FRAMEWORK_TYPE}" = "dart_frog" ]; then \
            # Dart Frog has its own build command
            dart pub global activate dart_frog_cli; \
            dart_frog build; \
            if [ -f "build/bin/server.exe" ]; then \
                mv build/bin/server.exe /home/dexfile/app/build/server; \
            fi; \
        elif [ -f "bin/server.dart" ]; then \
            dart compile exe bin/server.dart -o /home/dexfile/app/build/server; \
        elif [ -f "bin/main.dart" ]; then \
            dart compile exe bin/main.dart -o /home/dexfile/app/build/app; \
        elif [ -f "lib/main.dart" ]; then \
            dart compile exe lib/main.dart -o /home/dexfile/app/build/app; \
        else \
            echo "ERROR: No main entry point found for compilation" >&2; \
            exit 1; \
        fi; \
    # dart2js (Web compilation to JavaScript)
    elif [ "${DART_RUNTIME}" = "dart2js" ]; then \
        if [ -f "web/main.dart" ]; then \
            dart compile js web/main.dart -o /home/dexfile/app/build/web/main.dart.js -O4; \
            cp -r web/* /home/dexfile/app/build/web/ 2>/dev/null || true; \
            # Remove source dart files from output
            find /home/dexfile/app/build/web -name "*.dart" -delete; \
        else \
            echo "ERROR: No web/main.dart found for dart2js compilation" >&2; \
            exit 1; \
        fi; \
    # dart2wasm (Web compilation to WebAssembly)
    elif [ "${DART_RUNTIME}" = "dart2wasm" ]; then \
        if [ -f "web/main.dart" ]; then \
            dart compile wasm web/main.dart -o /home/dexfile/app/build/web/main.wasm; \
            cp -r web/* /home/dexfile/app/build/web/ 2>/dev/null || true; \
            find /home/dexfile/app/build/web -name "*.dart" -delete; \
        else \
            echo "ERROR: No web/main.dart found for dart2wasm compilation" >&2; \
            exit 1; \
        fi; \
    # JIT (Dart VM) - copy source and create kernel snapshot
    else \
        # Create kernel snapshot for faster startup
        if [ "${FRAMEWORK_TYPE}" = "dart_frog" ]; then \
            dart pub global activate dart_frog_cli; \
            dart_frog build; \
            cp -r build/* /home/dexfile/app/build/; \
        elif [ -f "bin/server.dart" ]; then \
            dart compile kernel bin/server.dart -o /home/dexfile/app/build/server.dill; \
            cp -r lib /home/dexfile/app/build/ 2>/dev/null || true; \
        elif [ -f "bin/main.dart" ]; then \
            dart compile kernel bin/main.dart -o /home/dexfile/app/build/app.dill; \
            cp -r lib /home/dexfile/app/build/ 2>/dev/null || true; \
        else \
            # Copy entire project for JIT mode
            cp -r . /home/dexfile/app/build/; \
        fi; \
    fi

# Framework-specific build steps
RUN set -e; \
    if [ "${FRAMEWORK_TYPE}" = "serverpod" ]; then \
        if [ -f "config/generator.yaml" ]; then \
            dart run serverpod_cli generate; \
        fi; \
    fi

# ============================================================================
# RUNTIME BASE STAGE
# ============================================================================
IF PROC [ "${DART_RUNTIME}" = "dart2js" ] || [ "${DART_RUNTIME}" = "dart2wasm" ]
    # Use web server for static content
    FROM ${RUN_IMAGE} AS app
ELSE IF PROC [ "${DART_RUNTIME}" = "native" ] || [ "${DART_RUNTIME}" = "aot" ]
    # Use minimal runtime for native executables
    FROM debian:bookworm-slim AS app
ELSE
    # Use Dart runtime for JIT mode
    FROM ${BUILD_IMAGE} AS app
ENDIF

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

ENV DART_ENV=production
ENV PORT=${PORT}
EXPOSE ${PORT}

# ============================================================================
# PRODUCTION STAGE
# ============================================================================
FROM app AS prod

# Handle static web serving (dart2js/wasm)
IF PROC [ "${DART_RUNTIME}" = "dart2js" ] || [ "${DART_RUNTIME}" = "dart2wasm" ]
    # Copy web server config
    IF PROC [ "${WEB_SERVER}" = "nginx" ]
        COPY --chown=root:root nginx.conf /etc/nginx/conf.d/default.conf 2>/dev/null || true
    ELSE IF PROC [ "${WEB_SERVER}" = "apache" ]
        COPY --chown=root:root apache.conf /usr/local/apache2/conf/httpd.conf 2>/dev/null || true
    ELSE IF PROC [ "${WEB_SERVER}" = "caddy" ]
        COPY --chown=root:root Caddyfile /etc/caddy/Caddyfile 2>/dev/null || true
    ENDIF
    
    # Copy compiled web assets
    COPY --chown=nginx:nginx --from=builder /home/dexfile/app/build/web ${NGINX_ROOT}/
    
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

# Handle native/AOT executables
ELSE IF PROC [ "${DART_RUNTIME}" = "native" ] || [ "${DART_RUNTIME}" = "aot" ]
    # Install minimal runtime dependencies
    RUN apt-get update && \
        apt-get install -y --no-install-recommends \
            ca-certificates \
            libssl3 \
            curl && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*
    
    # Copy compiled executable
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/build/server /home/dexfile/app/server 2>/dev/null || \
         COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/build/app /home/dexfile/app/app 2>/dev/null || true
    
    # Copy any required runtime assets
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/public /home/dexfile/app/public 2>/dev/null || true
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/config /home/dexfile/app/config 2>/dev/null || true
    
    USER dexfile:dexnore
    
    # Health check
    HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
        CMD curl -f http://127.0.0.1:${PORT}/health 2>/dev/null || \
            curl -f http://127.0.0.1:${PORT}/ || exit 1
    
    # Run the native executable
    IF PROC [ -f "/home/dexfile/app/server" ]
        CMD ["/home/dexfile/app/server"]
    ELSE
        CMD ["/home/dexfile/app/app"]
    ENDIF

# Handle JIT mode (Dart VM)
ELSE
    # Dart VM is already available in base image
    ENV DART_ENV=production
    ENV PUB_CACHE=/home/dexfile/.pub-cache
    
    # Copy dependencies
    COPY --chown=dexfile:dexnore --from=deps /home/dexfile/.pub-cache /home/dexfile/.pub-cache
    
    # Copy built application
    COPY --chown=dexfile:dexfile pubspec.yaml pubspec.lock /home/dexfile/app/
    
    IF PROC [ "${FRAMEWORK_TYPE}" = "dart_frog" ]
        # Dart Frog specific
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/build /home/dexfile/app/build
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/routes /home/dexfile/app/routes 2>/dev/null || true
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/public /home/dexfile/app/public 2>/dev/null || true
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "serverpod" ]
        # Serverpod specific
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/lib /home/dexfile/app/lib
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/bin /home/dexfile/app/bin
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/config /home/dexfile/app/config 2>/dev/null || true
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/generated /home/dexfile/app/generated 2>/dev/null || true
    ELSE
        # Generic Dart application
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/lib /home/dexfile/app/lib 2>/dev/null || true
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/bin /home/dexfile/app/bin 2>/dev/null || true
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/build/*.dill /home/dexfile/app/ 2>/dev/null || true
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/public /home/dexfile/app/public 2>/dev/null || true
    ENDIF
    
    USER dexfile:dexnore
    
    # Health check
    HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
        CMD curl -f http://127.0.0.1:${PORT}/health 2>/dev/null || \
            curl -f http://127.0.0.1:${PORT}/ || exit 1
    
    # Framework-specific entrypoints
    IF PROC [ "${FRAMEWORK_TYPE}" = "dart_frog" ]
        CMD ["dart", "build/bin/server.dill"]
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "serverpod" ]
        CMD ["dart", "run", "bin/main.dart"]
    ELSE IF PROC [ -f "/home/dexfile/app/server.dill" ]
        CMD ["dart", "run", "server.dill"]
    ELSE IF PROC [ -f "/home/dexfile/app/app.dill" ]
        CMD ["dart", "run", "app.dill"]
    ELSE IF PROC [ -f "bin/server.dart" ]
        CMD ["dart", "run", "bin/server.dart"]
    ELSE IF PROC [ -f "bin/main.dart" ]
        CMD ["dart", "run", "bin/main.dart"]
    ELSE
        CMD ["dart", "run"]
    ENDIF
ENDIF

# ============================================================================
# RELEASE STAGE
# ============================================================================
FROM prod AS release

# Metadata labels
LABEL maintainer="@dexnore/dexfile"
LABEL org.opencontainers.image.vendor="Dexnore"
LABEL org.opencontainers.image.title="Dart Application"
LABEL org.opencontainers.image.description="Production Dart application supporting JIT, AOT, dart2js, and dart2wasm"
LABEL org.opencontainers.image.authors="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

# Dynamic labels based on detection
LABEL app.runtime="${DART_RUNTIME}"
LABEL app.dart-version="${DART_VERSION}"
LABEL app.framework="${FRAMEWORK_TYPE}"
# LABEL app.app-server="${APP_SERVER}"
# LABEL app.asset-pipeline="${ASSET_PIPELINE}"
# LABEL app.workspace="${WORKSPACE_TYPE}"
# LABEL app.yjit-enabled="${ENABLE_YJIT}"
LABEL security.non-root="true"

FROM release