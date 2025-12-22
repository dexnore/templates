# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

IMPORT --file=./go/Dexfile \
    local:context \
    AS go

IMPORT --file=./node/Dexfile \
    local:context \
    AS node

IMPORT --file=./java/Dexfile \
    local:context \
    AS java

IMPORT --file=./python/Dexfile \
    local:context \
    AS python

IMPORT --file=./php/Dexfile \
    local:context \
    AS php

IMPORT --file=./ruby/Dexfile \
    local:context \
    AS ruby

IMPORT --file=./dart/Dexfile \
    local:context \
    AS dart

IMPORT --file=./csharp/Dexfile \
    local:context \
    AS csharp

IMPORT --file=./rust/Dexfile \
    local:context \
    AS rust

#####################################

IMPORT --file=./go/Dexfile \
    --target=meta-stage \
    local:context \
    AS go-detect

IMPORT --file=./node/Dexfile \
    --target=meta-stage \
    local:context \
    AS node-detect

IMPORT --file=./java/Dexfile \
    --target=meta-stage \
    local:context \
    AS java-detect

IMPORT --file=./python/Dexfile \
    --target=meta-stage \
    local:context \
    AS python-detect

IMPORT --file=./php/Dexfile \
    --target=meta-stage \
    local:context \
    AS php-detect

IMPORT --file=./ruby/Dexfile \
    --target=meta-stage \
    local:context \
    AS ruby-detect

IMPORT --file=./dart/Dexfile \
    --target=meta-stage \
    local:context \
    AS dart-detect

IMPORT --file=./csharp/Dexfile \
    --target=meta-stage \
    local:context \
    AS csharp-detect

IMPORT --file=./rust/Dexfile \
    --target=meta-stage \
    local:context \
    AS rust-detect

#####################################

FROM busybox:latest AS prod
IF BUILD node-detect
    BUILD node
ELSE IF BUILD go-detect
    BUILD go
ELSE IF BUILD java-detect
    BUILD java
ELSE IF BUILD python-detect
    BUILD python
ELSE IF BUILD php-detect
    BUILD php
ELSE IF BUILD ruby-detect
    BUILD ruby
ELSE IF BUILD dart-detect
    BUILD dart
ELSE IF BUILD csharp-detect
    BUILD csharp
ELSE IF BUILD rust-detect
    BUILD rust
ELSE
    RUN echo "no programming language detected" >&2 && \
        echo "supported programming languages:" >&2 && \
        echo "node, go, java, python, php, ruby, dart, csharp, rust" >&2 && \
        exit 1
ENDIF

FROM busybox:latest
IF BUILD prod
    BUILD prod
ELSE
    ARG STDERR=$STDERR
    RUN echo "${STDERR}" >&2 && \
        echo "please file a report at 'https://github.com/dexnore/templates' if it is unexpected" >&2 && \
        exit 1
ENDIF
