# syntax=dexnore/dexfile:0

# Production-ready Rust Dexfile supporting:
# - Frameworks: Axum, Actix-web, Rocket, Loco, Warp, Tide, Leptos, Dioxus, Poem, Salvo, Thruster
# - Build Tools: Cargo, Cargo Chef, Cargo Lambda, Cargo Workspace, Trunk (WASM), Maturin
# - Async Runtimes: Tokio, async-std, smol
# - Web Servers: nginx, Caddy (for static/WASM serving)
# - Workspaces: Cargo workspaces, multi-crate projects
# - Version Managers: rustup, .rust-version, rust-toolchain.toml

ARG RUST_VERSION CARGO_BUILD_TARGET BUILD_IMAGE="rust:alpine" RUN_IMAGE="debian:bookworm-slim"
ARG FRAMEWORK_TYPE ASYNC_RUNTIME BUILD_PROFILE=release WORKSPACE_TYPE
ARG PORT=8080 NGINX_ROOT="/usr/share/nginx/html"
ARG CARGO_CHEF_VERSION="0.1.68"

WORKDIR /home/dexfile/app

# ============================================================================
# RUST VERSION DETECTION
# ============================================================================
FUNC detect_rust_version
    # Priority 1: rust-toolchain.toml (most reliable, modern approach)
    IF PROC --from=busybox:latest --mount=target=. [ -f "rust-toolchain.toml" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP 'channel\s*=\s*"\K[^"]+' rust-toolchain.toml) && echo "$VERSION"
            ARG RUST_VERSION=${STDOUT}
        ENDIF
    # Priority 2: rust-toolchain (legacy format)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "rust-toolchain" ]
        ARG RUST_VERSION=$(cat rust-toolchain | tr -d '\n')
    # Priority 3: .rust-version (custom version file)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".rust-version" ]
        ARG RUST_VERSION=$(cat .rust-version | tr -d '\n')
    ELSE
        ARG RUST_VERSION="stable"
    ENDIF
    
    # Set build image based on detected version
    IF PROC [ -n "${RUST_VERSION}" ]
        ARG BUILD_IMAGE="rust:${RUST_VERSION}-alpine"
    ELSE
        ARG BUILD_IMAGE="rust:alpine"
    ENDIF
ENDFUNC

# ============================================================================
# FRAMEWORK DETECTION
# ============================================================================
FUNC detect_framework
    # Check Cargo.toml for framework dependencies
    IF PROC --from=busybox:latest --mount=target=. grep -q 'axum\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="axum"
        ARG ASYNC_RUNTIME="tokio"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'actix-web\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="actix-web"
        ARG ASYNC_RUNTIME="tokio"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'rocket\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="rocket"
        ARG ASYNC_RUNTIME="tokio"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'loco-rs\s*=' Cargo.toml || grep -q '\[workspace\]' Cargo.toml && grep -q 'loco' Cargo.toml
        ARG FRAMEWORK_TYPE="loco"
        ARG ASYNC_RUNTIME="tokio"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'warp\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="warp"
        ARG ASYNC_RUNTIME="tokio"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'tide\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="tide"
        ARG ASYNC_RUNTIME="async-std"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'leptos\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="leptos"
        ARG ASYNC_RUNTIME="tokio"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'dioxus\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="dioxus"
        ARG ASYNC_RUNTIME="tokio"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'poem\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="poem"
        ARG ASYNC_RUNTIME="tokio"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'salvo\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="salvo"
        ARG ASYNC_RUNTIME="tokio"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'thruster\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="thruster"
        ARG ASYNC_RUNTIME="tokio"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'hyper\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="hyper"
        ARG ASYNC_RUNTIME="tokio"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'tower\s*=' Cargo.toml
        ARG FRAMEWORK_TYPE="tower"
        ARG ASYNC_RUNTIME="tokio"
    ELSE
        ARG FRAMEWORK_TYPE="generic"
        # Detect async runtime if no framework detected
        IF PROC --from=busybox:latest --mount=target=. grep -q 'tokio\s*=' Cargo.toml
            ARG ASYNC_RUNTIME="tokio"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'async-std\s*=' Cargo.toml
            ARG ASYNC_RUNTIME="async-std"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'smol\s*=' Cargo.toml
            ARG ASYNC_RUNTIME="smol"
        ELSE
            ARG ASYNC_RUNTIME="none"
        ENDIF
    ENDIF
ENDFUNC

# ============================================================================
# WORKSPACE DETECTION
# ============================================================================
FUNC detect_workspace
    IF PROC --from=busybox:latest --mount=target=. grep -q '\[workspace\]' Cargo.toml
        ARG WORKSPACE_TYPE="workspace"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -d "crates" ] && [ $(find crates -name "Cargo.toml" | wc -l) -gt 1 ]
        ARG WORKSPACE_TYPE="multi-crate"
    ELSE
        ARG WORKSPACE_TYPE="single"
    ENDIF
ENDFUNC

# ============================================================================
# BUILD TOOL DETECTION
# ============================================================================
FUNC detect_build_tool
    # Check for specialized build tools
    IF PROC --from=busybox:latest --mount=target=. grep -q 'cargo-lambda' Cargo.toml || [ -f "Cargo-Lambda.toml" ]
        ARG BUILD_TOOL="cargo-lambda"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'trunk' Cargo.toml || [ -f "Trunk.toml" ]
        ARG BUILD_TOOL="trunk"
        # Trunk is for WASM builds (Leptos, Dioxus, Yew)
        ARG CARGO_BUILD_TARGET="wasm32-unknown-unknown"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'maturin' Cargo.toml || [ -f "pyproject.toml" ]
        ARG BUILD_TOOL="maturin"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'wasm-pack' Cargo.toml
        ARG BUILD_TOOL="wasm-pack"
        ARG CARGO_BUILD_TARGET="wasm32-unknown-unknown"
    ELSE
        ARG BUILD_TOOL="cargo"
    ENDIF
ENDFUNC

# ============================================================================
# TARGET DETECTION
# ============================================================================
FUNC detect_target
    # Check for cross-compilation targets
    IF PROC --from=busybox:latest --mount=target=. grep -q '\[target\.' Cargo.toml
        IF PROC --from=busybox:latest --mount=target=. TARGET=$(grep -oP '\[target\.\K[^\]]+' Cargo.toml | head -1) && echo "$TARGET"
            ARG CARGO_BUILD_TARGET=${STDOUT}
        ENDIF
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".cargo/config.toml" ]
        IF PROC --from=busybox:latest --mount=target=. grep -q 'target\s*=' .cargo/config.toml
            IF PROC --from=busybox:latest --mount=target=. TARGET=$(grep -oP 'target\s*=\s*"\K[^"]+' .cargo/config.toml) && echo "$TARGET"
                ARG CARGO_BUILD_TARGET=${STDOUT}
            ENDIF
        ENDIF
    ENDIF
ENDFUNC

# ============================================================================
# NGINX/STATIC DETECTION (for WASM/Leptos/Dioxus)
# ============================================================================
FUNC detect_static_serving
    IF PROC --from=busybox:latest --mount=target=. [ -f "nginx.conf" ]
        ARG RUN_IMAGE="nginx:stable-alpine"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Caddyfile" ]
        ARG RUN_IMAGE="caddy:2-alpine"
    ELSE IF PROC [ "${BUILD_TOOL}" = "trunk" ] || [ "${FRAMEWORK_TYPE}" = "leptos" ] || [ "${FRAMEWORK_TYPE}" = "dioxus" ]
        # WASM frameworks often need static serving
        ARG RUN_IMAGE="nginx:stable-alpine"
    ENDIF
ENDFUNC

# ============================================================================
# RUN DETECTIONS
# ============================================================================
FUNC CALL detect_rust_version
FUNC CALL detect_framework
FUNC CALL detect_workspace
FUNC CALL detect_build_tool
FUNC CALL detect_target
FUNC CALL detect_static_serving

# Validate Cargo.toml exists
IF PROC --from=busybox:latest --mount=target=. [ ! -f "Cargo.toml" ]
    RUN echo "ERROR: No Cargo.toml found" >&2 && exit 1
ENDIF

# ============================================================================
# CHEF PLANNER STAGE (for dependency caching)
# ============================================================================
FROM ${BUILD_IMAGE} AS chef

# Install cargo-chef for dependency caching
RUN apk add --no-cache musl-dev pkgconfig openssl-dev openssl-libs-static && \
    cargo install cargo-chef --version ${CARGO_CHEF_VERSION} --locked

WORKDIR /home/dexfile/app

# ============================================================================
# PLANNER STAGE
# ============================================================================
FROM chef AS planner

COPY Cargo.toml Cargo.lock* ./
COPY rust-toolchain.toml rust-toolchain* .rust-version* ./ 2>/dev/null || true
COPY .cargo/ ./.cargo/ 2>/dev/null || true

# Copy workspace members if they exist
IF PROC [ "${WORKSPACE_TYPE}" = "workspace" ] || [ "${WORKSPACE_TYPE}" = "multi-crate" ]
    COPY crates/ ./crates/ 2>/dev/null || true
    COPY members/ ./members/ 2>/dev/null || true
    COPY packages/ ./packages/ 2>/dev/null || true
ENDIF

# Copy source code for planning
COPY src/ ./src/ 2>/dev/null || true
COPY migrations/ ./migrations/ 2>/dev/null || true
COPY config/ ./config/ 2>/dev/null || true

RUN cargo chef prepare --recipe-path recipe.json

# ============================================================================
# BASE BUILD STAGE
# ============================================================================
FROM chef AS base

# Install build dependencies
RUN apk add --no-cache \
    musl-dev \
    pkgconfig \
    openssl-dev \
    openssl-libs-static \
    perl \
    make \
    libc-dev \
    gcc \
    g++ \
    git \
    curl \
    bash \
    ca-certificates \
    postgresql-dev \
    sqlite-dev

# Install rustup components based on version
RUN if [ "${RUST_VERSION}" != "stable" ] && [ "${RUST_VERSION}" != "nightly" ] && [ "${RUST_VERSION}" != "beta" ]; then \
        rustup install ${RUST_VERSION} && rustup default ${RUST_VERSION}; \
    elif [ "${RUST_VERSION}" = "nightly" ]; then \
        rustup install nightly && rustup default nightly; \
    elif [ "${RUST_VERSION}" = "beta" ]; then \
        rustup install beta && rustup default beta; \
    fi

# Add common targets
RUN rustup target add x86_64-unknown-linux-musl 2>/dev/null || true

# Add WASM target if needed
IF PROC [ "${BUILD_TOOL}" = "trunk" ] || [ "${BUILD_TOOL}" = "wasm-pack" ] || [ "${CARGO_BUILD_TARGET}" = "wasm32-unknown-unknown" ]
    RUN rustup target add wasm32-unknown-unknown
ENDIF

# Install specialized build tools
IF PROC [ "${BUILD_TOOL}" = "trunk" ]
    RUN cargo install --locked trunk
ELSE IF PROC [ "${BUILD_TOOL}" = "wasm-pack" ]
    RUN cargo install --locked wasm-pack
ELSE IF PROC [ "${BUILD_TOOL}" = "cargo-lambda" ]
    RUN cargo install --locked cargo-lambda
    RUN rustup target add x86_64-unknown-linux-musl aarch64-unknown-linux-musl
ELSE IF PROC [ "${BUILD_TOOL}" = "maturin" ]
    RUN apk add --no-cache python3 python3-dev py3-pip
    RUN pip3 install --no-cache-dir maturin
ENDIF

# Set environment variables for static linking
ENV RUSTFLAGS="-C target-feature=+crt-static -C link-arg=-static"
ENV PKG_CONFIG_ALL_STATIC=1
ENV PKG_CONFIG_ALLOW_CROSS=1

WORKDIR /home/dexfile/app

# ============================================================================
# DEPENDENCIES STAGE (cached layer)
# ============================================================================
FROM base AS dependencies

# Copy the recipe from planner
COPY --from=planner /home/dexfile/app/recipe.json recipe.json

# Build dependencies using cargo-chef
RUN --mount=type=cache,id=rust-cargo-registry,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,id=rust-cargo-git,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,id=rust-target,target=/home/dexfile/app/target,sharing=locked \
    set -e; \
    if [ -n "${CARGO_BUILD_TARGET}" ]; then \
        cargo chef cook --release --target ${CARGO_BUILD_TARGET} --recipe-path recipe.json; \
    else \
        cargo chef cook --release --recipe-path recipe.json; \
    fi

# ============================================================================
# BUILDER STAGE
# ============================================================================
FROM base AS builder

# Copy cached dependencies
COPY --from=dependencies /usr/local/cargo /usr/local/cargo
COPY --from=dependencies /home/dexfile/app/target /home/dexfile/app/target

# Copy all source files
COPY . .

# Build the application
RUN --mount=type=cache,id=rust-cargo-registry,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,id=rust-cargo-git,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,id=rust-target,target=/home/dexfile/app/target,sharing=locked \
    set -e; \
    if [ "${BUILD_TOOL}" = "trunk" ]; then \
        trunk build --release; \
    elif [ "${BUILD_TOOL}" = "wasm-pack" ]; then \
        wasm-pack build --target web --release; \
    elif [ "${BUILD_TOOL}" = "cargo-lambda" ]; then \
        cargo lambda build --release; \
    elif [ "${BUILD_TOOL}" = "maturin" ]; then \
        maturin build --release; \
    elif [ -n "${CARGO_BUILD_TARGET}" ]; then \
        cargo build --release --target ${CARGO_BUILD_TARGET}; \
        cp target/${CARGO_BUILD_TARGET}/release/* target/release/ 2>/dev/null || true; \
    else \
        cargo build --release; \
    fi && \
    if [ "${BUILD_TOOL}" != "trunk" ] && [ "${BUILD_TOOL}" != "wasm-pack" ]; then \
        if [ "${WORKSPACE_TYPE}" = "workspace" ]; then \
            find target/release -maxdepth 1 -type f -executable -exec cp {} /usr/local/bin/ \; 2>/dev/null || \
            find target/${CARGO_BUILD_TARGET}/release -maxdepth 1 -type f -executable -exec cp {} /usr/local/bin/ \; 2>/dev/null || true; \
        else \
            BIN_NAME=$(grep -oP '^name\s*=\s*"\K[^"]+' Cargo.toml | head -1); \
            if [ -f "target/release/${BIN_NAME}" ]; then \
                cp target/release/${BIN_NAME} /usr/local/bin/app; \
            elif [ -f "target/${CARGO_BUILD_TARGET}/release/${BIN_NAME}" ]; then \
                cp target/${CARGO_BUILD_TARGET}/release/${BIN_NAME} /usr/local/bin/app; \
            fi; \
        fi; \
    fi

# ============================================================================
# RUNTIME BASE STAGE
# ============================================================================
FROM ${RUN_IMAGE} AS app

# Create non-root user
RUN if command -v addgroup >/dev/null 2>&1; then \
        addgroup -S dexnore 2>/dev/null || true; \
        adduser -S -D -H -h /home/dexfile/app -s /sbin/nologin -G dexnore dexfile 2>/dev/null || true; \
    elif command -v groupadd >/dev/null 2>&1; then \
        groupadd -r dexnore 2>/dev/null || true; \
        useradd -r -g dexnore -d /home/dexfile/app -s /sbin/nologin dexfile 2>/dev/null || true; \
    fi && \
    mkdir -p /home/dexfile/app && \
    chown -R dexfile:dexnore /home/dexfile/app 2>/dev/null || chown -R 1000:1000 /home/dexfile/app

# Install runtime dependencies
RUN if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            ca-certificates \
            libssl3 \
            wget \
            curl && \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache ca-certificates libssl3 libgcc wget curl; \
    fi

WORKDIR /home/dexfile/app
USER dexfile:dexnore

ENV RUST_LOG=info
ENV PORT=${PORT}
EXPOSE ${PORT}

# ============================================================================
# PRODUCTION STAGE
# ============================================================================
FROM app AS prod

# Handle nginx/Caddy static serving (for WASM/Leptos/Dioxus)
IF PROC [ -n "${RUN_IMAGE}" ] && (echo "${RUN_IMAGE}" | grep -q "nginx\|caddy")
    # Copy nginx/Caddy config
    IF PROC --from=busybox:latest --mount=target=. [ -f "nginx.conf" ]
        COPY --chown=root:root nginx.conf /etc/nginx/conf.d/default.conf
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Caddyfile" ]
        COPY --chown=root:root Caddyfile /etc/caddy/Caddyfile
    ELSE IF PROC [ "${BUILD_TOOL}" = "trunk" ]
        # Create default nginx config for WASM apps
        RUN echo 'server { \
            listen 80; \
            root /usr/share/nginx/html; \
            index index.html; \
            location / { \
                try_files $uri $uri/ /index.html; \
            } \
            location ~* \.(js|css|wasm)$ { \
                expires 1y; \
                add_header Cache-Control "public, immutable"; \
            } \
        }' > /etc/nginx/conf.d/default.conf
    ENDIF
    
    # Copy built static files
    IF PROC [ "${BUILD_TOOL}" = "trunk" ]
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/dist ${NGINX_ROOT}/
    ELSE IF PROC [ "${BUILD_TOOL}" = "wasm-pack" ]
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/pkg ${NGINX_ROOT}/
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "leptos" ]
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/dist ${NGINX_ROOT}/
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "dioxus" ]
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/dist ${NGINX_ROOT}/
    ELSE
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/dist ${NGINX_ROOT}/ 2>/dev/null || \
             COPY --chown=nginx:nginx --from=builder /home/dexfile/app/public ${NGINX_ROOT}/
    ENDIF
    
    # Set proper permissions
    RUN chown -R nginx:nginx ${NGINX_ROOT} && chmod -R 755 ${NGINX_ROOT}
    
    # Start web server
    IF PROC echo "${RUN_IMAGE}" | grep -q "nginx"
        CMD ["nginx", "-g", "daemon off;"]
    ELSE
        CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]
    ENDIF

# Handle Rust binary runtime
ELSE
    # Copy the compiled binary
    IF PROC [ "${WORKSPACE_TYPE}" = "workspace" ]
        COPY --chown=dexfile:dexnore --from=builder /usr/local/bin/* /usr/local/bin/
    ELSE
        COPY --chown=dexfile:dexnore --from=builder /usr/local/bin/app /usr/local/bin/app
    ENDIF
    
    # Copy configuration files if they exist
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/config ./config 2>/dev/null || true
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/migrations ./migrations 2>/dev/null || true
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/assets ./assets 2>/dev/null || true
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/static ./static 2>/dev/null || true
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/templates ./templates 2>/dev/null || true
    
    # Framework-specific health checks
    IF PROC [ "${FRAMEWORK_TYPE}" = "axum" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/health 2>/dev/null || \
                wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/ || exit 1
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "actix-web" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/health 2>/dev/null || \
                wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/ || exit 1
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "rocket" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/ || exit 1
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "loco" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/_health 2>/dev/null || exit 1
    ENDIF
    
    # Set appropriate entrypoint
    IF PROC [ "${WORKSPACE_TYPE}" = "workspace" ]
        # For workspaces, the user should specify which binary to run via ENV or override CMD
        CMD ["/bin/sh", "-c", "exec ${APP_BINARY:-/usr/local/bin/app}"]
    ELSE
        CMD ["/usr/local/bin/app"]
    ENDIF
ENDIF

# ============================================================================
# RELEASE STAGE
# ============================================================================
FROM prod AS release

# Metadata labels
LABEL maintainer="@dexnore/dexfile"
LABEL org.opencontainers.image.vendor="Dexnore"
LABEL org.opencontainers.image.title="Rust Application"
LABEL org.opencontainers.image.description="Production Rust application supporting multiple frameworks, async runtimes, and build tools"
LABEL org.opencontainers.image.authors="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

# Dynamic labels based on detection
LABEL app.framework="${FRAMEWORK_TYPE}"
LABEL app.async-runtime="${ASYNC_RUNTIME}"
LABEL app.build-tool="${BUILD_TOOL}"
LABEL app.workspace="${WORKSPACE_TYPE}"
LABEL app.rust-version="${RUST_VERSION}"
LABEL security.non-root="true"

FROM release