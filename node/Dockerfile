# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

ARG BUILD_IMAGE RUN_IMAGE PORT BUILD_IMAGE_VERSION NGINX_ROOT
WORKDIR /home/dexfile/app
IF PROC --mount=target=. [ ! -f "package.json" ]
    RUN echo "no 'package.json' file found!" >&2 && exit 1;
ENDIF

IF PROC [ -z "${BUILD_IMAGE}" ]
    IF PROC --mount=target=. [ -f "bun.lockb" ] || [ -f "bun.lock" ]
        IF PROC --mount=target=. [ -z "${BUILD_IMAGE_VERSION}" ] && [ -f ".bun-version" ] && cat .bun-version
            ARG BUILD_IMAGE_VERSION=$STDOUT
        ENDIF
        ARG BUILD_IMAGE=oven/bun:${BUILD_IMAGE_VERSION:+${BUILD_IMAGE_VERSION}-}alpine
    ELSE IF PROC --mount=target=. [ -f "lock.json" ] || [ -s "deno.json" ] || [ -s "deno.jsonc" ]
        ARG BUILD_IMAGE=denoland/deno:alpine
    ENDIF
ENDIF

IF PROC [ -z "${RUN_IMAGE}" ]
    IF PROC --mount=target=. [ -f "nginx.conf" ]
        ARG RUN_IMAGE=nginx:stable-alpine-slim
    ENDIF
ENDIF

FROM ${BUILD_IMAGE:-node:lts-alpine} AS base
WORKDIR /home/dexfile/app

FROM base AS deps
COPY package.json package-lock.json* yarn.lock* .pnp.* \
    pnpm-lock.yaml* bun.lock* lock.json* deno.json* \
    bunfig.toml* .npmrc* .yarnrc.yml* nginx.conf* \
    /home/dexfile/app/
COPY .yarn* /home/dexfile/app/.yarn
RUN --mount=type=cache,target=.npm \
    --mount=type=secret,id=npmrc,target=.npmrc \
    --mount=type=secret,id=yarnrc,target=.yarnrc.yml \
    --mount=type=secret,id=bunfig,target=bunfig.toml \
    if [ -f "yarn.lock" ]; then \
        if ! command -v yarn >/dev/null 2>&1; then \
            npm install -g yarn@latest; \
        fi; \
    elif [ -f "pnpm-lock.yaml" ]; then \
        if ! command -v pnpm >/dev/null 2>&1; then \
            npm install -g pnpm; fi; \
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
    if [ ! -f "nx.json" ]; then exit 0; fi; \
    if [ -f "yarn.lock" ]; then yarn global add nx; \
    elif [ -f "pnpm-lock.yaml" ]; then pnpm add --global nx; \
    elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then bun add -g nx; \
    elif [ -f "lock.json" ] || [ -s "deno.json" ] || [ -s "deno.jsonc" ]; then \
        deno install -A -n nx npm:nx; \
    else npm add --global nx; fi;

FROM deps AS installer
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
    if [ -f "yarn.lock" ]; then \
        if yarn --version | grep -q '^1\.'; then yarn install --production --frozen-lockfile; \
        else yarn install --immutable --check-cache; fi; \
    elif [ -f "pnpm-lock.yaml" ]; then pnpm install --frozen-lockfile --prod; \
    elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then bun install --frozen-lockfile --production; \
    elif [ -f "lock.json" ] || [ -s "deno.json" ] || [ -s "deno.jsonc" ]; then \
        deno cache --lock=deno.lock --frozen deps.ts; \
    else npm ci --omit=dev; fi;

FROM deps AS builder
RUN apk add --no-cache python3 git libc6-compat
COPY / .
COPY --from=installer ./node_modules ./node_modules
RUN if [ -f "yarn.lock" ]; then yarn build; \
    elif [ -f "pnpm-lock.yaml" ]; then pnpm run build; \
    elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then bun run build; \
    elif [ -f "lock.json" ] || [ -s "deno.json" ] || [ -s "deno.jsonc" ]; then \
        deno task build --lock=deno.lock --frozen; \
    else npm run build; fi;

FROM ${RUN_IMAGE:-node:lts-alpine} AS app
RUN addgroup dexnore && adduser --ingroup dexnore dexfile --disabled-password
WORKDIR /home/dexfile/app
USER dexfile:dexnore

FROM app AS prod
COPY --chown=root:root nginx.conf* /etc/nginx/conf.d/default.conf
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

IF PROC --mount=target=. [ -f "nx.json" ] && [ ! -f "nginx.conf" ]
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dist/apps/* /home/dexfile/app/
ELSE IF PROC --mount=target=. [ ! -f "nx.json" ] && [ ! -f "nginx.conf" ]
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app /home/dexfile/app
ELSE IF PROC --mount=target=. [ ! -f "nx.json" ] && [ -f "nginx.conf" ]
    COPY --chown=root:root --from=builder /home/dexfile/app/* ${NGINX_ROOT}
ELSE
    COPY --chown=root:root --from=builder /home/dexfile/app/dist/apps/* ${NGINX_ROOT}
ENDIF

RUN cat <<'EOF' > /usr/local/bin/entrypoint.sh
#!/bin/sh

if [ -f "nginx.conf" ]; then
exec nginx -g "daemon off;"
elif [ -f "deno.json" ] || [ -f "deno.jsonc" ] || [ -f "lock.json" ]; then
exec deno task start
elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
exec bun run start
elif [ -f "yarn.lock" ]; then
exec yarn start
elif [ -f "pnpm-lock.yaml" ]; then
exec pnpm start
else
exec npm run start
fi
EOF

RUN chmod +x /usr/local/bin/entrypoint.sh
CMD [ "/usr/local/bin/entrypoint.sh" ]

FROM prod AS release
EXPOSE ${PORT:-3000}
LABEL maintainer="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

FROM release
