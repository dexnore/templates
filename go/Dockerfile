# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

#################################################
## TODO: need to support Makefiles             ##
#################################################

ARG GO_ENTRYPOINT=.
ARG GO_OUTPUT_BIN_PATH=/dexfile-app
ARG GO_LD_FLAGS="-s -w"
ARG GO_BUILD_TAGS="osusergo netgo static_build"
ARG BUILD_IMAGE \
    RUN_IMAGE
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
IF RUN [ ! -f "go.sum" ]
    RUN go mod tidy
ENDIF
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
    set -euo pipefail && \
    echo "Trying build from GO_ENTRYPOINT=$GO_ENTRYPOINT" && \
    if CGO_ENABLED=0 go build \
        -ldflags="$GO_LD_FLAGS" \
        -tags "$GO_BUILD_TAGS" \
        -o "$GO_OUTPUT_BIN_PATH" \
        "$GO_ENTRYPOINT"; then \
        echo "Build succeeded from GO_ENTRYPOINT"; \
    else \
        echo "Build from GO_ENTRYPOINT failed, detecting main package dynamically..." >&2 && \
        MAIN_DIRS=$(find . -type f -maxdepth 5 -name '*.go' \
            ! -name '*_test.go' \
            ! -path './vendor/*' \
            -exec grep -q '^package main' {} \; \
            -exec grep -q '^func main\s*(' {} \; \
            -print \
            | xargs -r -n1 dirname | sort -u) && \
        COUNT=$(echo "$MAIN_DIRS" | grep -c . || true) && \
        if [ "$COUNT" -eq 0 ]; then \
            echo "No main package found, build failed" >&2 && exit 1; \
        elif [ "$COUNT" -gt 1 ]; then \
            echo "Error: multiple main package directories found:" >&2 && \
            echo "$MAIN_DIRS" >&2 && \
            echo "Please set GO_ENTRYPOINT explicitly via build args." >&2 && \
            exit 1; \
        else \
            MAIN_DIR=$(echo "$MAIN_DIRS") && \
            echo "Detected main dir: $MAIN_DIR" && \
            CGO_ENABLED=0 go build \
                -ldflags="$GO_LD_FLAGS" \
                -tags "$GO_BUILD_TAGS" \
                -o "$GO_OUTPUT_BIN_PATH" \
                "$MAIN_DIR"; \
        fi; \
    fi

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
