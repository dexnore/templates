# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

ARG GO_ENTRYPOINT=.
ARG GO_OUTPUT_BIN_PATH=/dexfile-app
ARG GO_LD_FLAGS="-s -w"
ARG GO_BUILD_TAGS="osusergo netgo static_build"
ARG BUILD_IMAGE \
    RUN_IMAGE \
    GO_MAIN_GLOB \
    GOOS \
    GOARCH \
    GO_MULTI_BIN \
    CROSS_MATRIX \
    MAKE_ENABLED \
    MAKE_TARGET \
    JUST_ENABLED \
    JUST_TARGET \
    TASK_ENABLED \
    TASK_TARGET
WORKDIR /home/dexfile/app
# --- Validation Stage ---
IF PROC --mount=target=. [ ! -f "go.mod" ]
    RUN echo "Error: no 'go.mod' found. Go modules are required." >&2 && exit 1;
ENDIF

FROM alpine AS static
RUN apk add --no-cache \
    ca-certificates \
    tzdata

# minimal non-root user/group
RUN echo "dexfile:x:10001:10001:dexfile:/home/dexfile:/" > /etc/passwd && \
    echo "dexnore:x:10001:dexfile" > /etc/group

# minimal nsswitch to avoid libc/user lookup issues
RUN echo "passwd: files" > /etc/nsswitch.conf && \
    echo "group: files" >> /etc/nsswitch.conf

# required runtime directories
RUN mkdir -p /home/dexfile /tmp && \
    chmod 1777 /tmp && \
    chown -R 10001:10001 /home/dexfile

FROM ${BUILD_IMAGE:-golang:latest} AS base
WORKDIR /home/dexfile/app

# --- Build Stage ---
FROM base AS builder
COPY go.mod go.sum* /home/dexfile/app/
# Separate dependency download for better caching
RUN --mount=type=cache,target=/root/.cache,sharing=shared,id=dexfile-root-cache \
    --mount=type=cache,target=/go/pkg/mod,sharing=shared,id=dexfile-mod-cache \
    go mod download

ARG GO_ENTRYPOINT=$GO_ENTRYPOINT
ARG GO_OUTPUT_BIN_PATH=$GO_OUTPUT_BIN_PATH
ARG GO_LD_FLAGS=$GO_LD_FLAGS
ARG GO_BUILD_TAGS=$GO_BUILD_TAGS
RUN --mount=target=.,id=dexfile-app-src \
    --mount=type=cache,target=/root/.cache,sharing=shared,id=dexfile-root-cache \
    --mount=type=cache,target=/go/pkg/mod,sharing=shared,id=dexfile-mod-cache \
    <<EOF
#!/bin/sh
set -e

# 1. Validation of Meta ARGs
: "\${GO_OUTPUT_BIN_PATH?Error: GO_OUTPUT_BIN_PATH must be set}"

# 2. Dependencies
if [ -f go.mod ]; then
    case \${GOFLAGS:-} in (*-mod=vendor*) ;; *) go mod download >/dev/null 2>&1 || true ;; esac
fi

# 3. Build function
build_pkg() {
    _p="\$1" _o="\$2"
    env CGO_ENABLED=0 \
        \${GOOS:+GOOS="\$GOOS"} \
        \${GOARCH:+GOARCH="\$GOARCH"} \
        go build -trimpath \
        -ldflags="\${GO_LD_FLAGS:+\$GO_LD_FLAGS }-buildid=" \
        \${GO_BUILD_TAGS:+-tags="\$GO_BUILD_TAGS"} \
        -o "\$_o" "\$_p"
}

# 4. Detection
M=""

# 4.1 Check GO_ENTRYPOINT first
if [ -n "\${GO_ENTRYPOINT:-}" ]; then
    build_pkg "\${GO_ENTRYPOINT}" "\${GO_OUTPUT_BIN_PATH}" && exit 0
fi

# 4.2 Check GO_MAIN_GLOB
if [ -n "\${GO_MAIN_GLOB:-}" ]; then
    set -f; set -- \${GO_MAIN_GLOB}; set +f
    for d; do [ -d "\$d" ] && M="\$M\${M:+ }\$d"; done
fi

# 4.3 Fallback to Makefile / Justfile / Taskfile if no main packages yet
if [ -z "\$M" ]; then
    if [ "${MAKE_ENABLED:-1}" -eq 1 ] && [ -f Makefile ]; then
        make "${MAKE_TARGET:-build}" && exit 0
    elif [ "${JUST_ENABLED:-0}" -eq 1 ] && [ -f Justfile ]; then
        just "${JUST_TARGET:-build}" && exit 0
    elif [ "${TASK_ENABLED:-0}" -eq 1 ] && [ -f Taskfile.yml ]; then
        task "${TASK_TARGET:-build}" && exit 0
    fi
fi

# 4.4 If still nothing, try go.mod detection
if [ -z "\$M" ] && [ -f go.mod ]; then
    M=\$(go list \${GO_BUILD_TAGS:+-tags="\$GO_BUILD_TAGS"} -f '{{if eq .Name "main"}}{{.Dir}}{{end}}' ./... 2>/dev/null || true)
fi

# 4.5 Final check: fail if still no main packages
if [ -z "\$M" ]; then
    echo "No main packages found" >&2
    exit 1
fi

# 5. Execution Loop
_OIFS=\$IFS; IFS=' '
if [ -n "\$CROSS_MATRIX" ]; then
    _B_OUT="\${GO_OUTPUT_BIN_PATH}"
    _M_IFS=\$IFS; IFS=','; set -f; set -- \$CROSS_MATRIX; set +f; IFS=\$_M_IFS
    for c; do
        export GOOS="\${c%%/*}" GOARCH="\${c##*/}"
        MDIR="\$_B_OUT/\${GOOS}_\${GOARCH}"
        mkdir -p "\$MDIR"
        set -f; set -- \$M; set +f
        for p; do
            bin="\${p##*/}"; [ "\$GOOS" = windows ] && bin="\$bin.exe"
            tout="\$MDIR"; [ "\${GO_MULTI_BIN:-0}" = 1 ] && tout="\$MDIR/\$bin"
            build_pkg "\$p" "\$tout"
        done
    done
else
    [ "\${GO_MULTI_BIN:-0}" -eq 1 ] && mkdir -p "\${GO_OUTPUT_BIN_PATH}"
    set -f; set -- \$M; set +f
    for p; do
        tout="\${GO_OUTPUT_BIN_PATH}"
        [ "\${GO_MULTI_BIN:-0}" -eq 1 ] && tout="\${GO_OUTPUT_BIN_PATH}/\${p##*/}"
        build_pkg "\$p" "\$tout"
    done
fi
IFS=\$_OIFS
EOF

FROM ${RUN_IMAGE:-alpine:latest} AS prod
WORKDIR /home/dexfile/app
ARG GO_OUTPUT_BIN_PATH=$GO_OUTPUT_BIN_PATH
# Create a non-privileged user
IF RUN addgroup -S dexnore && adduser -S dexfile -G dexnore
    RUN addgroup -S dexnore && adduser -S dexfile -G dexnore
    COPY --from=builder --chown=dexnore:dexfile $GO_OUTPUT_BIN_PATH ./dexfile-app
    USER dexfile:dexnore
ELSE IF PROC --from=alpine [ "$RUN_IMAGE" = "scratch" ]
    # ---- essential envs ----
    ENV \
        HOME=/home/dexfile \
        TZ=UTC \
        SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    # TLS
    COPY --from=static /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

    # Timezones (safe to remove if UTC-only)
    COPY --from=static /usr/share/zoneinfo /usr/share/zoneinfo

    # User resolution
    COPY --from=static /etc/passwd /etc/passwd
    COPY --from=static /etc/group /etc/group
    COPY --from=static /etc/nsswitch.conf /etc/nsswitch.conf

    # Runtime directories
    COPY --from=static --chmod=1777 /tmp /tmp
    COPY --from=static --chown=10001:10001 /home/dexfile /home/dexfile
    COPY --from=builder --chown=10001:10001 $GO_OUTPUT_BIN_PATH ./dexfile-app
    USER 10001:10001
ELSE
    COPY --from=builder $GO_OUTPUT_BIN_PATH ./dexfile-app
ENDIF

FROM prod AS release
ENTRYPOINT [ "/home/dexfile/app/dexfile-app" ]
EXPOSE 3000
LABEL maintainer="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

FROM release
