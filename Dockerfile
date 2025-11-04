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

FROM busybox:latest AS prod
IF BUILD node
    BUILD node
ELSE IF BUILD go
    BUILD go
ELSE IF BUILD java
    BUILD java
ELSE IF BUILD python
    BUILD python
ELSE IF BUILD php
    BUILD php
ELSE IF BUILD ruby
    BUILD ruby
ELSE IF BUILD dart
    BUILD dart
ELSE IF BUILD csharp
    BUILD csharp
ELSE IF BUILD rust
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
