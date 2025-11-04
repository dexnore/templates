# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

ARG GO_ENTRYPOINT=.
ARG GO_OUTPUT_BIN_PATH=/dexfile-app
ARG LD_FLAGS
ARG BUILD_IMAGE \
    RUN_IMAGE
WORKDIR /home/dexfile/app
CTR --mount=target=. base-img
    IF PROC [ ! -f "go.mod" ]
        RUN echo "no 'go.mod' file found in the project" >&2 && exit 1;
    ENDIF
ENDCTR

FROM ${BUILD_IMAGE:-golang:latest} AS base
WORKDIR /home/dexfile/app

FROM base AS builder
COPY go.mod go.sum* /home/dexfile/app/
IF RUN [ ! -f "go.sum" ]
    RUN go mod tidy
ENDIF
RUN --mount=type=cache,target=/root/.cache,sharing=shared,id=dexfile-root-cache \
    --mount=type=cache,target=/go/pkg/mod,sharing=shared,id=dexfile-mod-cache \
    go mod download

ARG GO_ENTRYPOINT=$GO_ENTRYPOINT
ARG GO_OUTPUT_BIN_PATH=$GO_OUTPUT_BIN_PATH
ARG LD_FLAGS=$LD_FLAGS
RUN --mount=target=.,id=dexfile-app-src \
    --mount=type=cache,target=/root/.cache,sharing=shared,id=dexfile-root-cache \
    --mount=type=cache,target=/go/pkg/mod,sharing=shared,id=dexfile-mod-cache \
    set -euo pipefail && \
    echo "Trying build from GO_ENTRYPOINT=$GO_ENTRYPOINT" && \
    if CGO_ENABLED=0 go build \
        -ldflags="$LD_FLAGS" \
        -tags "osusergo netgo static_build" \
        -o "$GO_OUTPUT_BIN_PATH" \
        "$GO_ENTRYPOINT"; then \
        echo "Build succeeded from GO_ENTRYPOINT"; \
    else \
        echo "Build from GO_ENTRYPOINT failed, detecting main package dynamically..." >&2 && \
        MAIN_DIRS=$(find . -type f -name '*.go' \
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
                -ldflags="$LD_FLAGS" \
                -tags "osusergo netgo static_build" \
                -o "$GO_OUTPUT_BIN_PATH" \
                "$MAIN_DIR"; \
        fi; \
    fi

FROM ${RUN_IMAGE:-alpine:latest} AS prod
WORKDIR /home/dexfile/app
ARG GO_OUTPUT_BIN_PATH=$GO_OUTPUT_BIN_PATH
COPY --from=builder $GO_OUTPUT_BIN_PATH ./dexfile-app

FROM prod AS release
ENTRYPOINT [ "/home/dexfile/app/dexfile-app" ]
EXPOSE 3000
LABEL maintainer="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

FROM release
