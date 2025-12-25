# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

ARG BUILD_IMAGE RUN_IMAGE PORT BUILD_IMAGE_VERSION NGINX_ROOT WORKSPACE_TYPE PACKAGE_MANAGER
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

FUNC CALL detect_package_manager

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

FUNC CALL detect_workspace

IF PROC [ -z "${BUILD_IMAGE_VERSION}" ]
	IF PROC --from=busybox:latest --mount=target=. [ -f ".bun-version" ] && cat .bun-version
		ARG BUILD_IMAGE_VERSION=$STDOUT
	ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"packageManager".*"bun@' package.json; && VERSION=$(grep -oP '"packageManager":\s*"bun@\K[^"]+' package.json) && echo "$VERSION"
		ARG BUILD_IMAGE_VERSION=$STDOUT
	ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".deno-version" ] && cat .deno-version
		ARG BUILD_IMAGE_VERSION=$STDOUT
	# Node.js version detection (priority order)
	# 1. .nvmrc (most common)
	ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".nvmrc" ] && cat .nvmrc | tr -d 'v' | tr -d '\n'
		ARG BUILD_IMAGE_VERSION=$STDOUT
	# 2. .node-version (asdf, fnm)
	ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".node-version" ] && cat .node-version | tr -d 'v' | tr -d '\n'
		ARG BUILD_IMAGE_VERSION=$STDOUT
	# 3. .tool-versions (asdf)
	ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".tool-versions" ] && VERSION=$(grep -oP 'nodejs\s+\K[\d.]+' .tool-versions) && echo "$VERSION"
		ARG BUILD_IMAGE_VERSION=$STDOUT
	# 4. volta field in package.json
	ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"volta"' package.json; && VERSION=$(grep -oP '"node":\s*"\K[\d.]+' package.json) && echo "$VERSION"
		ARG BUILD_IMAGE_VERSION=$STDOUT
	# 5. engines field in package.json
	ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '"engines"' package.json; && VERSION=$(grep -oP '"node":\s*"[>=^~]*\K[\d.]+' package.json | head -1) && echo "$VERSION"
		ARG BUILD_IMAGE_VERSION=$STDOUT
	ENDIF
ENDIF

IF PROC [ -z "${BUILD_IMAGE}" ]
    # Bun version detection
    IF PROC [ "${PACKAGE_MANAGER}" = "bun" ]
        ARG BUILD_IMAGE=oven/bun:${BUILD_IMAGE_VERSION:+${BUILD_IMAGE_VERSION}-}alpine
	# Deno version detection
    ELSE IF PROC [ "${PACKAGE_MANAGER}" = "deno" ]
		ARG BUILD_IMAGE=denoland/deno:alpine${BUILD_IMAGE_VERSION:+-${BUILD_IMAGE_VERSION}}
	ELSE
		ARG BUILD_IMAGE="node:${BUILD_IMAGE_VERSION:+${BUILD_IMAGE_VERSION}-}${BUILD_IMAGE_VERSION:-lts}alpine"
	ENDIF
ENDIF

IF PROC [ -z "${RUN_IMAGE}" ]
	IF PROC --mount=target=. [ -f "nginx.conf" ]
		ARG RUN_IMAGE=nginx:stable-alpine-slim
	ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Caddyfile" ]
        ARG RUN_IMAGE="caddy:2-alpine"
	# Bun version detection
    ELSE IF PROC [ "${PACKAGE_MANAGER}" = "bun" ]
        ARG RUN_IMAGE=oven/bun:${BUILD_IMAGE_VERSION:+${BUILD_IMAGE_VERSION}-}alpine
	# Deno version detection
    ELSE IF PROC [ "${PACKAGE_MANAGER}" = "deno" ]
		ARG RUN_IMAGE=denoland/deno:alpine${BUILD_IMAGE_VERSION:+-${BUILD_IMAGE_VERSION}}
	ELSE
		ARG RUN_IMAGE="node:${BUILD_IMAGE_VERSION:+${BUILD_IMAGE_VERSION}-}${BUILD_IMAGE_VERSION:-lts}alpine"
	ENDIF
ENDIF

FROM ${BUILD_IMAGE:-node:lts-alpine} AS base
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

FROM base AS deps
COPY package.json package-lock.json* yarn.lock* .pnp.* \
    pnpm-lock.yaml* bun.lock* lock.json* deno.json* \
    bunfig.toml* .npmrc* .yarnrc.yml* nginx.conf* \
	bunfig.toml* nx.json* turbo.json* lerna.json* rush.json* pnpm-workspace.yaml* \
    /home/dexfile/app/
COPY .yarn* /home/dexfile/app/.yarn
RUN --mount=type=cache,target=.npm \
    --mount=type=secret,id=npmrc,target=.npmrc \
    --mount=type=secret,id=yarnrc,target=.yarnrc.yml \
    --mount=type=secret,id=bunfig,target=bunfig.toml \
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
    fi;

RUN --mount=type=cache,target=.npm \
    --mount=type=cache,target=.cache/yarn \
    --mount=type=cache,target=.yarn/cache \
    --mount=type=cache,target=.pnpm-store \
    --mount=type=cache,target=.local/share/pnpm/store/v3 \
    --mount=type=cache,target=.bun/install/cache \
    --mount=type=cache,target=.cache/deno \
    --mount=type=secret,id=npmrc,target=.npmrc \
    --mount=type=secret,id=yarnrc,target=.yarnrc.yml \
    --mount=type=secret,id=bunfig,target=bunfig.toml \
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


FROM deps AS installer
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

FROM deps AS builder
RUN apk add --no-cache python3 git libc6-compat
COPY / .
COPY --from=installer ./node_modules ./node_modules
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

FROM ${RUN_IMAGE:-node:lts-alpine} AS app
RUN addgroup dexnore && adduser --ingroup dexnore dexfile --disabled-password
WORKDIR /home/dexfile/app
USER dexfile:dexnore

FROM app AS prod
RUN cat <<'EOF' > /usr/local/bin/nginx_custom_script.sh
#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Functions (library part)
# -----------------------------

declare -A _visited_files=()

with_nullglob() {
  local saved_state
  saved_state=$(shopt -p nullglob)
  shopt -s nullglob
  "$@"
  eval "$saved_state"
}

inline_includes() {
  local file="$1"
  local dir
  dir=$(dirname "$file")
  if [[ -n "${_visited_files[$file]:-}" ]]; then return; fi
  _visited_files[$file]=1
  while IFS= read -r line || [[ -n $line ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^include[[:space:]]+(.+);$ ]]; then
      IFS=' ' read -r -a patterns <<< "${BASH_REMATCH[1]}"
      for pattern in "${patterns[@]}"; do
        [[ "$pattern" != /* ]] && pattern="$dir/$pattern"
        local files
        with_nullglob files=( $pattern )
        for f in "${files[@]}"; do
          [[ -f "$f" ]] && inline_includes "$f"
        done
      done
    else
      echo "$line"
    fi
  done < "$file"
}

count_chars() { local string=$1 char=$2 count=0 i; for ((i=0;i<${#string};i++)); do [[ "${string:i:1}" == "$char" ]] && ((count++)); done; echo $count; }

extract_server_block() {
  local conf="$1" conf_cleaned server_count=0 server_block="" current_block="" in_server=0 depth=0
  conf_cleaned=$(inline_includes "$conf")
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ "$line" =~ ^server[[:space:]]*\{ ]] && (( in_server == 0 )); then in_server=1; depth=1; current_block="$line"$'\n'; continue; fi
    if (( in_server == 1 )); then
      depth=$((depth + $(count_chars "$line" "{") - $(count_chars "$line" "}")))
      current_block+="$line"$'\n'
      if (( depth == 0 )); then server_count=$((server_count+1)); server_block="$current_block"; in_server=0; fi
    fi
  done <<< "$conf_cleaned"
  if (( server_count != 1 )); then echo "❌ Error: Found $server_count server blocks" >&2; return 1; fi
  echo "$server_block"
}

nginx_get_listen_ports() {
  local conf="$1" block ports=()
  block=$(extract_server_block "$conf") || return 1
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*listen[[:space:]]+(.+) ]] || continue
    local rest="${BASH_REMATCH[1]}"
    for token in $rest; do
      [[ "$token" =~ default_server|ssl|http2|proxy_protocol|reuseport ]] && continue
      token="${token%%;}" token="${token##*\]}" token="${token##*:}"
      [[ "$token" =~ ^[0-9]+$ ]] || continue
      ports+=("$token")
    done
  done <<< "$block"
  readarray -t ports < <(printf "%s\n" "${ports[@]}" | sort -u)
  if (( ${#ports[@]} == 0 )); then echo "<none>"; else for p in "${ports[@]}"; do echo "$p"; done; fi
}

nginx_get_root() {
  local conf="$1" block roots=() root
  block=$(extract_server_block "$conf") || return 1
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*root[[:space:]]+(.+) ]] || continue
    root="${BASH_REMATCH[1]}"
    root="${root%%;}" root="${root#\"}" root="${root%\"}"
    roots+=("$root")
  done <<< "$block"
  local in_blk=0 depth=0 blk=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*(location[[:space:]]+|if[[:space:]]*\() ]]; then in_blk=1; depth=1; blk="$line"$'\n'; continue; fi
    if (( in_blk == 1 )); then
      depth=$((depth + $(count_chars "$line" "{") - $(count_chars "$line" "}")))
      blk+="$line"$'\n'
      if (( depth == 0 )); then
        while IFS= read -r l; do
          [[ "$l" =~ ^[[:space:]]*root[[:space:]]+(.+) ]] || continue
          root="${BASH_REMATCH[1]}"
          root="${root%%;}" root="${root#\"}" root="${root%\"}"
          roots+=("$root")
        done <<< "$blk"
        in_blk=0
      fi
    fi
  done <<< "$block"
  readarray -t roots < <(printf "%s\n" "${roots[@]}" | sort -u)
  if (( ${#roots[@]} == 0 )); then echo "❌ Error: No root found" >&2; return 1; fi
  if (( ${#roots[@]} > 1 )); then echo "❌ Error: Multiple roots found: ${roots[*]}" >&2; return 1; fi
  echo "${roots[0]}"
}

# -----------------------------
# CLI execution
# -----------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if (( $# != 2 )); then
    echo "Usage: $0 [root|ports] /path/to/nginx.conf" >&2
    exit 1
  fi

  mode="$1"
  conf_file="$2"

  if [[ "$mode" == "ports" ]]; then
    nginx_get_listen_ports "$conf_file" || exit 1
  elif [[ "$mode" == "root" ]]; then
    nginx_get_root "$conf_file" || exit 1
  else
    echo "Usage: $0 [root|ports] /path/to/nginx.conf" >&2
    exit 1
  fi
fi

EOF
RUN chmod +x /usr/local/bin/nginx_custom_script.sh

FOR PORT IN RUN /usr/local/bin/nginx_custom_script.sh ports nginx.conf
    ARG PORT=${PORT}
    EXPOSE ${PORT}
ENDFOR

ARG NGINX_ROOT=${NGINX_ROOT}
IF RUN /usr/local/bin/nginx_custom_script.sh root nginx.conf && [ -z "${NGINX_ROOT}" ]
    ARG NGINX_ROOT=${STDOUT:-/usr/share/nginx/html}
ENDIF

IF PROC [ -n "${RUN_IMAGE}" ] && (echo "${RUN_IMAGE}" | grep -q "nginx\|caddy")
	# Copy nginx/Caddy config
	IF PROC --from=busybox:latest --mount=target=. [ -f "nginx.conf" ]
		COPY --chown=root:root nginx.conf /etc/nginx/conf.d/default.conf
	ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Caddyfile" ]
		COPY --chown=root:root Caddyfile /etc/caddy/Caddyfile
	ENDIF
ELSE
	# Copy production dependencies
    COPY --chown=dexfile:dexnore --from=deps /home/dexfile/app/node_modules* ./
    COPY --chown=dexfile:dexnore --from=deps /home/dexfile/app/.pnp.* ./
    COPY --chown=dexfile:dexnore --from=deps /home/dexfile/app/.yarn* ./
    
    # Copy package.json
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/package.json ./package.json

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
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/dist* ${NGINX_ROOT}/
		COPY --chown=nginx:nginx --from=builder /home/dexfile/app/build* ${NGINX_ROOT}/
		COPY --chown=nginx:nginx --from=builder /home/dexfile/app/public* ${NGINX_ROOT}/
		COPY --chown=nginx:nginx --from=builder /home/dexfile/app/out* ${NGINX_ROOT}/
    ENDIF

	# Set proper permissions
    RUN chown -R nginx:nginx ${NGINX_ROOT} && chmod -R 755 ${NGINX_ROOT}

	# Start web server
    IF PROC echo "${RUN_IMAGE}" | grep -q "nginx"
        CMD ["nginx", "-g", "daemon off;"]
    ELSE
        CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]
    ENDIF


	# Copy built application based on framework
    IF PROC [ "${WORKSPACE_TYPE}" = "nx" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist ./dist
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "nextjs" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/.next* ./
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/public* ./
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/next.config.* ./
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "nuxt" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/.output* ./
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "remix" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/build* ./
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/public* ./
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "astro" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist* ./
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "sveltekit" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/build* ./
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "angular" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist* ./
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "nestjs" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist* ./
    ELSE
        # Generic: copy common output directories
		COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist* ./
		COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/build* ./
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

# IF PROC --mount=target=. [ -f "nx.json" ] && [ ! -f "nginx.conf" ]
#     COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist/apps/* /home/dexfile/app/
# ELSE IF PROC --mount=target=. [ ! -f "nx.json" ] && [ ! -f "nginx.conf" ]
#     COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app /home/dexfile/app
# ELSE IF PROC --mount=target=. [ ! -f "nx.json" ] && [ -f "nginx.conf" ]
#     COPY --chown=root:root --from=builder /home/dexfile/app/* ${NGINX_ROOT}
# ELSE
#     COPY --chown=root:root --from=builder /home/dexfile/app/dist/apps/* ${NGINX_ROOT}
# ENDIF

# RUN cat <<'EOF' > /usr/local/bin/entrypoint.sh
# #!/bin/sh

# if [ -f "nginx.conf" ]; then
# exec nginx -g "daemon off;"
# elif [ -f "deno.json" ] || [ -f "deno.jsonc" ] || [ -f "lock.json" ]; then
# exec deno task start
# elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
# exec bun run start
# elif [ -f "yarn.lock" ]; then
# exec yarn start
# elif [ -f "pnpm-lock.yaml" ]; then
# exec pnpm start
# else
# exec npm run start
# fi
# EOF

# RUN chmod +x /usr/local/bin/entrypoint.sh
# CMD [ "/usr/local/bin/entrypoint.sh" ]

FROM prod AS release
EXPOSE ${PORT:-3000}
LABEL maintainer="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

FROM release
