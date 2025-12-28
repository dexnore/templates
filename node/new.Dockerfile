# syntax=dexnore/dexfile:0

# Production-ready Node.js Dexfile supporting:
# - Runtimes: Node.js, Bun, Deno
# - Package Managers: npm, yarn (1/2/3/4), pnpm, bun, deno
# - Version Managers: nvm, volta, asdf, corepack
# - Frameworks: Next.js, Nuxt, Remix, Astro, SvelteKit, Qwik, Solid Start, Angular, Vue, React
# - Backend: Express, Fastify, NestJS, Hono, Koa, Hapi, Oak (Deno)
# - Build Tools: Vite, Webpack, esbuild, Rollup, Turbopack, Parcel, Rspack
# - Monorepos: Nx, Turborepo, Lerna, Rush, Yarn/pnpm workspaces
# - Servers: nginx, Caddy, static serving
# - Process Managers: PM2, node --watch, tsx --watch

ARG BUILD_IMAGE RUN_IMAGE PORT=3000 RUNTIME_VERSION NODE_ENV=production
ARG PACKAGE_MANAGER FRAMEWORK_TYPE BUILD_TOOL WORKSPACE_TYPE
ARG NGINX_ROOT="/usr/share/nginx/html"

WORKDIR /home/dexfile/app

# ============================================================================
# PACKAGE MANAGER DETECTION
# ============================================================================
FUNC detect_package_manager
    # Priority 1: Lock files (most reliable)
    IF PROC --from=busybox:latest --mount=target=. [ -f "bun.lockb" ] || [ -f "bun.lock" ]
        ARG PACKAGE_MANAGER="bun"
        ARG BUILD_IMAGE="oven/bun:alpine"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "deno.lock" ] || [ -f "deno.json" ] || [ -f "deno.jsonc" ]
        ARG PACKAGE_MANAGER="deno"
        ARG BUILD_IMAGE="denoland/deno:alpine"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "pnpm-lock.yaml" ]
        ARG PACKAGE_MANAGER="pnpm"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "yarn.lock" ]
        ARG PACKAGE_MANAGER="yarn"
        # Detect Yarn version from lockfile
        IF PROC --from=busybox:latest --mount=target=. grep -q "__metadata" yarn.lock
            ARG PACKAGE_MANAGER="yarn-berry"
        ENDIF
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "package-lock.json" ]
        ARG PACKAGE_MANAGER="npm"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "package.json" ]
        # Check packageManager field in package.json
        IF PROC --from=busybox:latest --mount=target=. grep -q '"packageManager".*"pnpm@' package.json
            ARG PACKAGE_MANAGER="pnpm"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"packageManager".*"yarn@' package.json
            ARG PACKAGE_MANAGER="yarn-berry"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"packageManager".*"bun@' package.json
            ARG PACKAGE_MANAGER="bun"
            ARG BUILD_IMAGE="oven/bun:alpine"
        ELSE
            ARG PACKAGE_MANAGER="npm"
        ENDIF
    ELSE
        RUN echo "ERROR: No package.json found" >&2 && exit 1
    ENDIF
ENDFUNC

# ============================================================================
# VERSION DETECTION
# ============================================================================
FUNC detect_runtime_version
    # Bun version detection
    IF PROC [ "${PACKAGE_MANAGER}" = "bun" ]
        IF PROC --from=busybox:latest --mount=target=. [ -f ".bun-version" ]
            ARG RUNTIME_VERSION=$(cat .bun-version)
            ARG BUILD_IMAGE="oven/bun:${RUNTIME_VERSION}-alpine"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"packageManager".*"bun@' package.json
            IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP '"packageManager":\s*"bun@\K[^"]+' package.json) && echo "$VERSION"
                ARG RUNTIME_VERSION=${STDOUT}
                ARG BUILD_IMAGE="oven/bun:${RUNTIME_VERSION}-alpine"
            ENDIF
        ENDIF
        RETURN
    ENDIF
    
    # Deno version detection
    IF PROC [ "${PACKAGE_MANAGER}" = "deno" ]
        IF PROC --from=busybox:latest --mount=target=. [ -f ".deno-version" ]
            ARG RUNTIME_VERSION=$(cat .deno-version)
            ARG BUILD_IMAGE="denoland/deno:alpine-${RUNTIME_VERSION}"
        ENDIF
        RETURN
    ENDIF
    
    # Node.js version detection (priority order)
    # 1. .nvmrc (most common)
    IF PROC --from=busybox:latest --mount=target=. [ -f ".nvmrc" ]
        ARG RUNTIME_VERSION=$(cat .nvmrc | tr -d 'v' | tr -d '\n')
    # 2. .node-version (asdf, fnm)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".node-version" ]
        ARG RUNTIME_VERSION=$(cat .node-version | tr -d 'v' | tr -d '\n')
    # 3. .tool-versions (asdf)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".tool-versions" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP 'nodejs\s+\K[\d.]+' .tool-versions) && echo "$VERSION"
            ARG RUNTIME_VERSION=${STDOUT}
        ENDIF
    # 4. volta field in package.json
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"volta"' package.json
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP '"node":\s*"\K[\d.]+' package.json) && echo "$VERSION"
            ARG RUNTIME_VERSION=${STDOUT}
        ENDIF
    # 5. engines field in package.json
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"engines"' package.json
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP '"node":\s*"[>=^~]*\K[\d.]+' package.json | head -1) && echo "$VERSION"
            ARG RUNTIME_VERSION=${STDOUT}
        ENDIF
    ENDIF
    
    # Set Node.js build image
    IF PROC [ -n "${RUNTIME_VERSION}" ]
        ARG BUILD_IMAGE="node:${RUNTIME_VERSION}-alpine"
    ELSE
        ARG BUILD_IMAGE="node:lts-alpine"
    ENDIF
ENDFUNC

# ============================================================================
# FRAMEWORK DETECTION
# ============================================================================
FUNC detect_framework
    # Check dependencies in package.json for framework detection
    IF PROC --from=busybox:latest --mount=target=. grep -q '"next"' package.json
        ARG FRAMEWORK_TYPE="nextjs"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"nuxt"' package.json
        ARG FRAMEWORK_TYPE="nuxt"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"@remix-run' package.json
        ARG FRAMEWORK_TYPE="remix"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"astro"' package.json
        ARG FRAMEWORK_TYPE="astro"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"@sveltejs/kit"' package.json
        ARG FRAMEWORK_TYPE="sveltekit"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"@builder.io/qwik"' package.json
        ARG FRAMEWORK_TYPE="qwik"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"@solidjs/start"' package.json
        ARG FRAMEWORK_TYPE="solidstart"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"@angular/core"' package.json
        ARG FRAMEWORK_TYPE="angular"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"@nestjs/core"' package.json
        ARG FRAMEWORK_TYPE="nestjs"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"express"' package.json
        ARG FRAMEWORK_TYPE="express"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"fastify"' package.json
        ARG FRAMEWORK_TYPE="fastify"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"hono"' package.json
        ARG FRAMEWORK_TYPE="hono"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"@oak/oak"' package.json
        ARG FRAMEWORK_TYPE="oak"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"koa"' package.json
        ARG FRAMEWORK_TYPE="koa"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"@hapi/hapi"' package.json
        ARG FRAMEWORK_TYPE="hapi"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"vue"' package.json && ! grep -q '"nuxt"' package.json
        ARG FRAMEWORK_TYPE="vue"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"react"' package.json && ! grep -q '"next"' package.json
        ARG FRAMEWORK_TYPE="react"
    ELSE
        ARG FRAMEWORK_TYPE="generic"
    ENDIF
ENDFUNC

# ============================================================================
# BUILD TOOL DETECTION
# ============================================================================
FUNC detect_build_tool
    # Check for build tools in package.json
    IF PROC --from=busybox:latest --mount=target=. grep -q '"vite"' package.json || [ -f "vite.config.js" ] || [ -f "vite.config.ts" ] || [ -f "vite.config.mjs" ]
        ARG BUILD_TOOL="vite"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"webpack"' package.json || [ -f "webpack.config.js" ] || [ -f "webpack.config.ts" ]
        ARG BUILD_TOOL="webpack"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"esbuild"' package.json || [ -f "esbuild.config.js" ]
        ARG BUILD_TOOL="esbuild"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"rollup"' package.json || [ -f "rollup.config.js" ] || [ -f "rollup.config.ts" ]
        ARG BUILD_TOOL="rollup"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"turbo"' package.json || [ -f "turbo.json" ]
        ARG BUILD_TOOL="turbopack"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"parcel"' package.json || [ -f ".parcelrc" ]
        ARG BUILD_TOOL="parcel"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"@rspack' package.json || [ -f "rspack.config.js" ]
        ARG BUILD_TOOL="rspack"
    ELSE
        ARG BUILD_TOOL="none"
    ENDIF
ENDFUNC

# ============================================================================
# WORKSPACE/MONOREPO DETECTION
# ============================================================================
FUNC detect_workspace
    IF PROC --from=busybox:latest --mount=target=. [ -f "nx.json" ]
        ARG WORKSPACE_TYPE="nx"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "turbo.json" ]
        ARG WORKSPACE_TYPE="turborepo"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "lerna.json" ]
        ARG WORKSPACE_TYPE="lerna"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "rush.json" ]
        ARG WORKSPACE_TYPE="rush"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"workspaces"' package.json
        ARG WORKSPACE_TYPE="workspaces"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "pnpm-workspace.yaml" ]
        ARG WORKSPACE_TYPE="pnpm-workspaces"
    ELSE
        ARG WORKSPACE_TYPE="single"
    ENDIF
ENDFUNC

# ============================================================================
# NGINX DETECTION
# ============================================================================
FUNC detect_nginx
    IF PROC --from=busybox:latest --mount=target=. [ -f "nginx.conf" ]
        ARG RUN_IMAGE="nginx:stable-alpine"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Caddyfile" ]
        ARG RUN_IMAGE="caddy:2-alpine"
    ENDIF
ENDFUNC

# ============================================================================
# RUN DETECTIONS
# ============================================================================
FUNC CALL detect_package_manager
FUNC CALL detect_runtime_version
FUNC CALL detect_framework
FUNC CALL detect_build_tool
FUNC CALL detect_workspace
FUNC CALL detect_nginx

# Validate package.json exists
IF PROC --from=busybox:latest --mount=target=. [ ! -f "package.json" ] && [ ! -f "deno.json" ] && [ ! -f "deno.jsonc" ]
    RUN echo "ERROR: No package.json, deno.json, or deno.jsonc found" >&2 && exit 1
ENDIF

# ============================================================================
# BASE BUILD STAGE
# ============================================================================
FROM ${BUILD_IMAGE} AS base
WORKDIR /home/dexfile/app

# Install system dependencies for native modules
RUN if command -v apk >/dev/null 2>&1; then \
        apk add --no-cache \
            python3 py3-pip make g++ gcc git \
            libc6-compat libstdc++ \
            curl bash; \
    elif command -v apt-get >/dev/null 2>&1; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            python3 python3-pip make g++ gcc git curl && \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# Enable Corepack for Yarn/pnpm management (Node.js 16.10+)
RUN if command -v corepack >/dev/null 2>&1; then \
        corepack enable; \
        corepack prepare pnpm@latest --activate 2>/dev/null || true; \
        corepack prepare yarn@stable --activate 2>/dev/null || true; \
    fi

# Set environment variables
ENV NODE_ENV=production
ENV NPM_CONFIG_LOGLEVEL=warn
ENV NPM_CONFIG_UPDATE_NOTIFIER=false
ENV HUSKY=0
ENV CI=true

# ============================================================================
# DEPENDENCY INSTALLATION STAGE
# ============================================================================
FROM base AS deps

# Copy package manager files and configs
COPY package.json package-lock.json* yarn.lock* pnpm-lock.yaml* \
     bun.lockb* bun.lock* deno.json* deno.jsonc* deno.lock* \
     .npmrc* .yarnrc* .yarnrc.yml* bunfig.toml* \
     nx.json* turbo.json* lerna.json* rush.json* pnpm-workspace.yaml* \
     /home/dexfile/app/

# Copy workspace and config directories
COPY .yarn/ /home/dexfile/app/.yarn/ 2>/dev/null || true
COPY .pnp.* /home/dexfile/app/ 2>/dev/null || true
COPY .config/ /home/dexfile/app/.config/ 2>/dev/null || true

# Install package manager globally if needed
RUN --mount=type=cache,id=npm-cache,target=/root/.npm,sharing=locked \
    --mount=type=secret,id=npmrc,target=/home/dexfile/app/.npmrc \
    --mount=type=secret,id=yarnrc,target=/home/dexfile/app/.yarnrc.yml \
    --mount=type=secret,id=bunfig,target=/home/dexfile/app/bunfig.toml \
    set -e; \
    if [ "${PACKAGE_MANAGER}" = "pnpm" ] && ! command -v pnpm >/dev/null 2>&1; then \
        if command -v corepack >/dev/null 2>&1; then \
            corepack enable pnpm; \
        else \
            npm install -g pnpm@latest; \
        fi; \
    elif [ "${PACKAGE_MANAGER}" = "yarn" ] || [ "${PACKAGE_MANAGER}" = "yarn-berry" ]; then \
        if ! command -v yarn >/dev/null 2>&1; then \
            if command -v corepack >/dev/null 2>&1; then \
                corepack enable yarn; \
            else \
                npm install -g yarn@latest; \
            fi; \
        fi; \
    fi

# Install monorepo tools globally if needed
RUN --mount=type=cache,id=npm-cache,target=/root/.npm,sharing=locked \
    --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    --mount=type=cache,id=yarn-cache,target=/root/.yarn/cache,sharing=locked \
    --mount=type=secret,id=npmrc,target=/home/dexfile/app/.npmrc \
    set -e; \
    if [ "${WORKSPACE_TYPE}" = "nx" ] && [ -f "nx.json" ]; then \
        if [ "${PACKAGE_MANAGER}" = "pnpm" ]; then \
            pnpm add -g nx@latest; \
        elif [ "${PACKAGE_MANAGER}" = "yarn" ] || [ "${PACKAGE_MANAGER}" = "yarn-berry" ]; then \
            yarn global add nx@latest 2>/dev/null || npm install -g nx@latest; \
        elif [ "${PACKAGE_MANAGER}" = "bun" ]; then \
            bun add -g nx@latest; \
        else \
            npm install -g nx@latest; \
        fi; \
    elif [ "${WORKSPACE_TYPE}" = "turborepo" ] && [ -f "turbo.json" ]; then \
        if [ "${PACKAGE_MANAGER}" = "pnpm" ]; then \
            pnpm add -g turbo@latest; \
        elif [ "${PACKAGE_MANAGER}" = "bun" ]; then \
            bun add -g turbo@latest; \
        else \
            npm install -g turbo@latest; \
        fi; \
    elif [ "${WORKSPACE_TYPE}" = "lerna" ] && [ -f "lerna.json" ]; then \
        npm install -g lerna@latest; \
    fi

# Install production dependencies
RUN --mount=type=cache,id=npm-cache,target=/root/.npm,sharing=locked \
    --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    --mount=type=cache,id=yarn-cache,target=/root/.yarn/cache,sharing=locked \
    --mount=type=cache,id=bun-cache,target=/root/.bun/install/cache,sharing=locked \
    --mount=type=cache,id=deno-cache,target=/root/.cache/deno,sharing=locked \
    --mount=type=secret,id=npmrc,target=/home/dexfile/app/.npmrc \
    --mount=type=secret,id=yarnrc,target=/home/dexfile/app/.yarnrc.yml \
    --mount=type=secret,id=bunfig,target=/home/dexfile/app/bunfig.toml \
    set -e; \
    if [ "${PACKAGE_MANAGER}" = "bun" ]; then \
        bun install --frozen-lockfile --production; \
    elif [ "${PACKAGE_MANAGER}" = "deno" ]; then \
        if [ -f "deno.lock" ]; then \
            deno cache --lock=deno.lock --frozen main.ts || deno cache --lock=deno.lock --frozen mod.ts || true; \
        fi; \
    elif [ "${PACKAGE_MANAGER}" = "pnpm" ]; then \
        pnpm install --frozen-lockfile --prod --prefer-offline; \
    elif [ "${PACKAGE_MANAGER}" = "yarn-berry" ]; then \
        yarn install --immutable --mode=skip-build; \
    elif [ "${PACKAGE_MANAGER}" = "yarn" ]; then \
        if yarn --version | grep -q '^1\.'; then \
            yarn install --frozen-lockfile --production --prefer-offline; \
        else \
            yarn install --immutable --mode=skip-build; \
        fi; \
    else \
        npm ci --omit=dev --prefer-offline; \
    fi

# ============================================================================
# BUILDER STAGE (Install ALL deps + build)
# ============================================================================
FROM base AS builder

# Copy all source files
COPY . .

# Install ALL dependencies (including dev dependencies)
RUN --mount=type=cache,id=npm-cache,target=/root/.npm,sharing=locked \
    --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    --mount=type=cache,id=yarn-cache,target=/root/.yarn/cache,sharing=locked \
    --mount=type=cache,id=bun-cache,target=/root/.bun/install/cache,sharing=locked \
    --mount=type=cache,id=deno-cache,target=/root/.cache/deno,sharing=locked \
    --mount=type=secret,id=npmrc,target=/home/dexfile/app/.npmrc \
    --mount=type=secret,id=yarnrc,target=/home/dexfile/app/.yarnrc.yml \
    --mount=type=secret,id=bunfig,target=/home/dexfile/app/bunfig.toml \
    set -e; \
    if [ "${PACKAGE_MANAGER}" = "bun" ]; then \
        bun install --frozen-lockfile; \
    elif [ "${PACKAGE_MANAGER}" = "deno" ]; then \
        if [ -f "deno.lock" ]; then \
            deno cache --lock=deno.lock main.ts || deno cache --lock=deno.lock mod.ts || true; \
        fi; \
    elif [ "${PACKAGE_MANAGER}" = "pnpm" ]; then \
        pnpm install --frozen-lockfile --prefer-offline; \
    elif [ "${PACKAGE_MANAGER}" = "yarn-berry" ]; then \
        yarn install --immutable; \
    elif [ "${PACKAGE_MANAGER}" = "yarn" ]; then \
        if yarn --version | grep -q '^1\.'; then \
            yarn install --frozen-lockfile --prefer-offline; \
        else \
            yarn install --immutable; \
        fi; \
    else \
        npm ci --prefer-offline; \
    fi

# Build the application
RUN --mount=type=cache,id=vite-cache,target=/home/dexfile/app/.vite,sharing=locked \
    --mount=type=cache,id=next-cache,target=/home/dexfile/app/.next/cache,sharing=locked \
    --mount=type=cache,id=nuxt-cache,target=/home/dexfile/app/.nuxt,sharing=locked \
    --mount=type=cache,id=turbo-cache,target=/home/dexfile/app/.turbo,sharing=locked \
    set -e; \
    if [ "${PACKAGE_MANAGER}" = "bun" ]; then \
        bun run build 2>/dev/null || echo "No build script found, skipping"; \
    elif [ "${PACKAGE_MANAGER}" = "deno" ]; then \
        if [ -f "deno.json" ] || [ -f "deno.jsonc" ]; then \
            deno task build 2>/dev/null || echo "No build task found, skipping"; \
        fi; \
    elif [ "${PACKAGE_MANAGER}" = "pnpm" ]; then \
        pnpm run build 2>/dev/null || pnpm build 2>/dev/null || echo "No build script found, skipping"; \
    elif [ "${PACKAGE_MANAGER}" = "yarn" ] || [ "${PACKAGE_MANAGER}" = "yarn-berry" ]; then \
        yarn build 2>/dev/null || echo "No build script found, skipping"; \
    else \
        npm run build 2>/dev/null || echo "No build script found, skipping"; \
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

WORKDIR /home/dexfile/app
USER dexfile:dexnore

ENV NODE_ENV=production
ENV PORT=${PORT}
EXPOSE ${PORT}

# ============================================================================
# PRODUCTION STAGE
# ============================================================================
FROM app AS prod

# Handle nginx/Caddy static serving
IF PROC [ -n "${RUN_IMAGE}" ] && (echo "${RUN_IMAGE}" | grep -q "nginx\|caddy")
    # Copy nginx/Caddy config
    IF PROC --from=busybox:latest --mount=target=. [ -f "nginx.conf" ]
        COPY --chown=root:root nginx.conf /etc/nginx/conf.d/default.conf
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Caddyfile" ]
        COPY --chown=root:root Caddyfile /etc/caddy/Caddyfile
    ENDIF
    
    # Copy built static files based on framework
    IF PROC [ "${WORKSPACE_TYPE}" = "nx" ]
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/dist/apps ${NGINX_ROOT}/
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "nextjs" ]
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/out ${NGINX_ROOT}/
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "nuxt" ]
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/.output/public ${NGINX_ROOT}/
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "astro" ]
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/dist ${NGINX_ROOT}/
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "sveltekit" ]
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/build ${NGINX_ROOT}/
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "angular" ]
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/dist ${NGINX_ROOT}/
    ELSE
        # Generic: try common output directories
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/dist ${NGINX_ROOT}/ 2>/dev/null || \
             COPY --chown=nginx:nginx --from=builder /home/dexfile/app/build ${NGINX_ROOT}/ 2>/dev/null || \
             COPY --chown=nginx:nginx --from=builder /home/dexfile/app/public ${NGINX_ROOT}/ 2>/dev/null || \
             COPY --chown=nginx:nginx --from=builder /home/dexfile/app/out ${NGINX_ROOT}/
    ENDIF
    
    # Set proper permissions
    RUN chown -R nginx:nginx ${NGINX_ROOT} && chmod -R 755 ${NGINX_ROOT}
    
    # Start web server
    IF PROC echo "${RUN_IMAGE}" | grep -q "nginx"
        CMD ["nginx", "-g", "daemon off;"]
    ELSE
        CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]
    ENDIF

# Handle Node.js/Bun/Deno runtime
ELSE
    # Copy production dependencies
    COPY --chown=dexfile:dexnore --from=deps /home/dexfile/app/node_modules ./node_modules 2>/dev/null || true
    COPY --chown=dexfile:dexnore --from=deps /home/dexfile/app/.pnp.* ./ 2>/dev/null || true
    COPY --chown=dexfile:dexnore --from=deps /home/dexfile/app/.yarn ./.yarn 2>/dev/null || true
    
    # Copy package.json
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/package.json ./package.json
    
    # Copy built application based on framework
    IF PROC [ "${WORKSPACE_TYPE}" = "nx" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist ./dist
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "nextjs" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/.next ./.next
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/public ./public 2>/dev/null || true
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/next.config.* ./ 2>/dev/null || true
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "nuxt" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/.output ./.output
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "remix" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/build ./build
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/public ./public 2>/dev/null || true
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "astro" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist ./dist
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "sveltekit" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/build ./build
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "angular" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist ./dist
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "nestjs" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist ./dist
    ELSE
        # Generic: copy common output directories
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist ./dist 2>/dev/null || \
             COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/build ./build 2>/dev/null || \
             COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app .
    ENDIF
    
    # Framework-specific health checks
    IF PROC [ "${FRAMEWORK_TYPE}" = "nextjs" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/api/health 2>/dev/null || \
                wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/ || exit 1
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "nestjs" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/health 2>/dev/null || exit 1
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "fastify" ] || [ "${FRAMEWORK_TYPE}" = "express" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/health 2>/dev/null || \
                wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/ || exit 1
    ENDIF
    
    # Set appropriate entrypoint based on framework and package manager
    IF PROC [ "${FRAMEWORK_TYPE}" = "nextjs" ]
        CMD ["node", "server.js"]
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "nuxt" ]
        CMD ["node", ".output/server/index.mjs"]
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "remix" ]
        IF PROC [ "${PACKAGE_MANAGER}" = "bun" ]
            CMD ["bun", "run", "start"]
        ELSE IF PROC [ "${PACKAGE_MANAGER}" = "pnpm" ]
            CMD ["pnpm", "start"]
        ELSE IF PROC [ "${PACKAGE_MANAGER}" = "yarn" ] || [ "${PACKAGE_MANAGER}" = "yarn-berry" ]
            CMD ["yarn", "start"]
        ELSE
            CMD ["npm", "start"]
        ENDIF
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "nestjs" ]
        CMD ["node", "dist/main"]
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "astro" ]
        CMD ["node", "./dist/server/entry.mjs"]
    ELSE IF PROC [ "${PACKAGE_MANAGER}" = "bun" ]
        CMD ["bun", "run", "start"]
    ELSE IF PROC [ "${PACKAGE_MANAGER}" = "deno" ]
        CMD ["deno", "task", "start"]
    ELSE IF PROC [ "${PACKAGE_MANAGER}" = "pnpm" ]
        CMD ["pnpm", "start"]
    ELSE IF PROC [ "${PACKAGE_MANAGER}" = "yarn" ] || [ "${PACKAGE_MANAGER}" = "yarn-berry" ]
        CMD ["yarn", "start"]
    ELSE
        CMD ["npm", "start"]
    ENDIF
ENDIF

# ============================================================================
# RELEASE STAGE
# ============================================================================
FROM prod AS release

# Metadata labels
LABEL maintainer="@dexnore/dexfile"
LABEL org.opencontainers.image.vendor="Dexnore"
LABEL org.opencontainers.image.title="Node.js Application"
LABEL org.opencontainers.image.description="Production Node.js application supporting multiple runtimes, frameworks, and build tools"
LABEL org.opencontainers.image.authors="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

# Dynamic labels based on detection
LABEL app.runtime="${PACKAGE_MANAGER}"
LABEL app.framework="${FRAMEWORK_TYPE}"
LABEL app.build-tool="${BUILD_TOOL}"
LABEL app.workspace="${WORKSPACE_TYPE}"
LABEL security.non-root="true"

FROM release