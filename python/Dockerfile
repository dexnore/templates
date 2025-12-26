# syntax=dexnore/dexfile:0

# ========================================================================================
# Universal Production-Ready Python Dexfile
# ========================================================================================
# Supports:
# - Runtimes: CPython, PyPy, GraalPy
# - Package Managers: pip, poetry, pipenv, uv, pdm, hatch, rye, conda/mamba
# - Frameworks: Django, FastAPI, Flask, Litestar, Starlette, Quart, Sanic, Tornado, Pyramid
# - ASGI Servers: Uvicorn, Hypercorn, Daphne, Granian
# - WSGI Servers: Gunicorn, uWSGI, Waitress
# - Task Queues: Celery, RQ, Dramatiq, Huey, Taskiq
# - Web Servers: Nginx, Caddy (as reverse proxy)
# ========================================================================================

# ========================
# Meta Stage: Global Args
# ========================
ARG PYTHON_VERSION=3.12
ARG RUNTIME_TYPE=cpython
ARG BASE_OS=debian
ARG PACKAGE_MANAGER=auto
ARG FRAMEWORK=auto
ARG SERVER=auto
ARG PORT=8000
ARG WORKERS=auto
ARG ENABLE_CELERY=auto
ARG ENABLE_NGINX=false

# ========================
# Stage 0: Project Validation
# ========================
FROM busybox:latest AS validator

WORKDIR /validate
COPY . .

# Validate Python project exists
RUN if ! find . -maxdepth 3 -type f \( \
        -name "*.py" -o \
        -name "pyproject.toml" -o \
        -name "requirements.txt" -o \
        -name "setup.py" -o \
        -name "Pipfile" -o \
        -name "environment.yml" -o \
        -name "poetry.lock" -o \
        -name "uv.lock" -o \
        -name "pdm.lock" \
    \) 2>/dev/null | grep -q .; then \
        echo "❌ ERROR: No Python project files found" >&2; \
        exit 1; \
    fi && \
    echo "✅ Python project validated"

# ========================
# Stage 1: Python Version Detection
# ========================
FROM busybox:latest AS python-version-detector

WORKDIR /detect
COPY . .

RUN sh -c ' \
    VERSION=""; \
    \
    if [ -f ".python-version" ]; then \
        VERSION=$(cat .python-version | head -1 | tr -d " \t\r\n" | grep -oE "[0-9]+\.[0-9]+"); \
        echo "Detected from .python-version: $VERSION"; \
    fi; \
    \
    if [ -z "$VERSION" ] && [ -f "pyproject.toml" ]; then \
        VERSION=$(grep -oP "requires-python\s*=\s*\"\K[^\"]*" pyproject.toml | grep -oE "[0-9]+\.[0-9]+" | sort -V | tail -1); \
        [ -n "$VERSION" ] && echo "Detected from pyproject.toml: $VERSION"; \
    fi; \
    \
    if [ -z "$VERSION" ] && [ -f "setup.py" ]; then \
        VERSION=$(grep -oP "python_requires\s*=\s*[\x27\"]?\K[^\x27\"]*" setup.py | grep -oE "[0-9]+\.[0-9]+" | sort -V | tail -1); \
        [ -n "$VERSION" ] && echo "Detected from setup.py: $VERSION"; \
    fi; \
    \
    if [ -z "$VERSION" ] && [ -f "Pipfile" ]; then \
        VERSION=$(grep -A5 "\[requires\]" Pipfile | grep -oP "python_version\s*=\s*\"\K[^\"]*" | head -1); \
        [ -n "$VERSION" ] && echo "Detected from Pipfile: $VERSION"; \
    fi; \
    \
    if [ -z "$VERSION" ] && [ -f "runtime.txt" ]; then \
        VERSION=$(grep -oP "python-\K[0-9]+\.[0-9]+" runtime.txt | head -1); \
        [ -n "$VERSION" ] && echo "Detected from runtime.txt: $VERSION"; \
    fi; \
    \
    if [ -z "$VERSION" ] && [ -f "tox.ini" ]; then \
        VERSION=$(grep -oP "py[0-9]+" tox.ini | head -1 | sed "s/py//; s/\([0-9]\)\([0-9]\)/\1.\2/"); \
        [ -n "$VERSION" ] && echo "Detected from tox.ini: $VERSION"; \
    fi; \
    \
    if [ -z "$VERSION" ]; then \
        VERSION="3.12"; \
        echo "No version found, defaulting to: $VERSION"; \
    fi; \
    \
    echo "$VERSION" > /detect/python_version.txt; \
    cat /detect/python_version.txt'

# ========================
# Stage 2: Runtime Type Detection
# ========================
FROM busybox:latest AS runtime-detector

WORKDIR /detect
COPY . .

RUN sh -c ' \
    RUNTIME="cpython"; \
    \
    if [ -f ".python-version" ]; then \
        CONTENT=$(cat .python-version); \
        if echo "$CONTENT" | grep -qi "pypy"; then \
            RUNTIME="pypy"; \
        elif echo "$CONTENT" | grep -qi "graalpy"; then \
            RUNTIME="graalpy"; \
        fi; \
    fi; \
    \
    echo "$RUNTIME" > /detect/runtime_type.txt; \
    echo "Detected runtime: $RUNTIME"'

# ========================
# Stage 3: Package Manager Detection
# ========================
FROM busybox:latest AS package-manager-detector

WORKDIR /detect
COPY . .

RUN sh -c ' \
    PM=""; \
    \
    if [ -f "uv.lock" ]; then \
        PM="uv"; \
    elif [ -f "rye.lock" ]; then \
        PM="rye"; \
    elif [ -f "pdm.lock" ]; then \
        PM="pdm"; \
    elif [ -f "poetry.lock" ]; then \
        PM="poetry"; \
    elif [ -f "Pipfile.lock" ] || [ -f "Pipfile" ]; then \
        PM="pipenv"; \
    elif [ -f "environment.yml" ] || [ -f "environment.yaml" ]; then \
        PM="conda"; \
    elif [ -f "pyproject.toml" ]; then \
        if grep -q "\[tool.hatch\]" pyproject.toml 2>/dev/null; then \
            PM="hatch"; \
        elif grep -q "\[tool.rye\]" pyproject.toml 2>/dev/null; then \
            PM="rye"; \
        elif grep -q "\[tool.pdm\]" pyproject.toml 2>/dev/null; then \
            PM="pdm"; \
        elif grep -q "\[tool.poetry\]" pyproject.toml 2>/dev/null; then \
            PM="poetry"; \
        elif grep -q "\[tool.uv\]" pyproject.toml 2>/dev/null; then \
            PM="uv"; \
        else \
            PM="pip"; \
        fi; \
    elif [ -f "requirements.txt" ] || [ -d "requirements" ]; then \
        PM="pip"; \
    elif [ -f "setup.py" ] || [ -f "setup.cfg" ]; then \
        PM="pip"; \
    else \
        echo "❌ ERROR: No package manager detected" >&2; \
        exit 1; \
    fi; \
    \
    echo "$PM" > /detect/package_manager.txt; \
    echo "Detected package manager: $PM"'

# ========================
# Stage 4: Framework Detection
# ========================
FROM busybox:latest AS framework-detector

WORKDIR /detect
COPY . .

RUN sh -c ' \
    FRAMEWORK="generic"; \
    \
    FILES=$(find . -maxdepth 2 -type f \( \
        -name "pyproject.toml" -o \
        -name "setup.py" -o \
        -name "setup.cfg" -o \
        -name "requirements.txt" -o \
        -name "Pipfile" \
    \) 2>/dev/null); \
    \
    if echo "$FILES" | xargs grep -l "django\|Django" 2>/dev/null | grep -q .; then \
        FRAMEWORK="django"; \
    elif echo "$FILES" | xargs grep -l "fastapi\|FastAPI" 2>/dev/null | grep -q .; then \
        FRAMEWORK="fastapi"; \
    elif echo "$FILES" | xargs grep -l "litestar\|Litestar" 2>/dev/null | grep -q .; then \
        FRAMEWORK="litestar"; \
    elif echo "$FILES" | xargs grep -l "flask\|Flask" 2>/dev/null | grep -q .; then \
        FRAMEWORK="flask"; \
    elif echo "$FILES" | xargs grep -l "quart\|Quart" 2>/dev/null | grep -q .; then \
        FRAMEWORK="quart"; \
    elif echo "$FILES" | xargs grep -l "sanic\|Sanic" 2>/dev/null | grep -q .; then \
        FRAMEWORK="sanic"; \
    elif echo "$FILES" | xargs grep -l "tornado\|Tornado" 2>/dev/null | grep -q .; then \
        FRAMEWORK="tornado"; \
    elif echo "$FILES" | xargs grep -l "pyramid\|Pyramid" 2>/dev/null | grep -q .; then \
        FRAMEWORK="pyramid"; \
    elif echo "$FILES" | xargs grep -l "starlette\|Starlette" 2>/dev/null | grep -q .; then \
        FRAMEWORK="starlette"; \
    fi; \
    \
    echo "$FRAMEWORK" > /detect/framework.txt; \
    echo "Detected framework: $FRAMEWORK"'

# ========================
# Stage 5: Server Detection
# ========================
FROM busybox:latest AS server-detector

WORKDIR /detect
COPY --from=framework-detector /detect/framework.txt ./
COPY . .

RUN sh -c ' \
    FRAMEWORK=$(cat framework.txt); \
    SERVER="uvicorn"; \
    \
    FILES=$(find . -maxdepth 2 -type f \( \
        -name "pyproject.toml" -o \
        -name "requirements.txt" -o \
        -name "Pipfile" \
    \) 2>/dev/null); \
    \
    if [ "$FRAMEWORK" = "django" ]; then \
        if echo "$FILES" | xargs grep -l "channels\|daphne" 2>/dev/null | grep -q .; then \
            SERVER="daphne"; \
        else \
            SERVER="gunicorn"; \
        fi; \
    elif [ "$FRAMEWORK" = "fastapi" ] || [ "$FRAMEWORK" = "litestar" ] || [ "$FRAMEWORK" = "starlette" ]; then \
        if echo "$FILES" | xargs grep -l "granian" 2>/dev/null | grep -q .; then \
            SERVER="granian"; \
        elif echo "$FILES" | xargs grep -l "hypercorn" 2>/dev/null | grep -q .; then \
            SERVER="hypercorn"; \
        else \
            SERVER="uvicorn"; \
        fi; \
    elif [ "$FRAMEWORK" = "flask" ] || [ "$FRAMEWORK" = "pyramid" ]; then \
        if echo "$FILES" | xargs grep -l "waitress" 2>/dev/null | grep -q .; then \
            SERVER="waitress"; \
        elif echo "$FILES" | xargs grep -l "uwsgi" 2>/dev/null | grep -q .; then \
            SERVER="uwsgi"; \
        else \
            SERVER="gunicorn"; \
        fi; \
    elif [ "$FRAMEWORK" = "sanic" ]; then \
        SERVER="sanic"; \
    elif [ "$FRAMEWORK" = "tornado" ]; then \
        SERVER="tornado"; \
    elif [ "$FRAMEWORK" = "quart" ]; then \
        SERVER="hypercorn"; \
    fi; \
    \
    echo "$SERVER" > /detect/server.txt; \
    echo "Detected server: $SERVER"'

# ========================
# Stage 6: Task Queue Detection
# ========================
FROM busybox:latest AS celery-detector

WORKDIR /detect
COPY . .

RUN sh -c ' \
    ENABLE_CELERY="false"; \
    \
    FILES=$(find . -maxdepth 2 -type f \( \
        -name "pyproject.toml" -o \
        -name "requirements.txt" -o \
        -name "Pipfile" \
    \) 2>/dev/null); \
    \
    if echo "$FILES" | xargs grep -l "celery\|Celery\|rq\|dramatiq\|huey\|taskiq" 2>/dev/null | grep -q .; then \
        ENABLE_CELERY="true"; \
    fi; \
    \
    echo "$ENABLE_CELERY" > /detect/celery.txt; \
    echo "Celery/Task queue enabled: $ENABLE_CELERY"'

# ========================
# Stage 7: Base Image Selection
# ========================
COPY --from=python-version-detector /detect/python_version.txt /tmp/
COPY --from=runtime-detector /detect/runtime_type.txt /tmp/
COPY --from=package-manager-detector /detect/package_manager.txt /tmp/

PROC cat /tmp/python_version.txt
ARG DETECTED_PYTHON_VERSION="${STDOUT}"

PROC cat /tmp/runtime_type.txt
ARG DETECTED_RUNTIME="${STDOUT}"

PROC cat /tmp/package_manager.txt
ARG DETECTED_PM="${STDOUT}"

# Select base image
IF RUN [ "${DETECTED_PM}" = "conda" ]
    ARG BUILD_IMAGE="continuumio/miniconda3:latest"
    ARG RUN_IMAGE="continuumio/miniconda3:latest"
ELSE IF RUN [ "${DETECTED_RUNTIME}" = "pypy" ]
    ARG BUILD_IMAGE="pypy:${DETECTED_PYTHON_VERSION}-slim"
    ARG RUN_IMAGE="pypy:${DETECTED_PYTHON_VERSION}-slim"
ELSE IF RUN [ "${BASE_OS}" = "alpine" ]
    ARG BUILD_IMAGE="python:${DETECTED_PYTHON_VERSION}-alpine"
    ARG RUN_IMAGE="python:${DETECTED_PYTHON_VERSION}-alpine"
ELSE
    ARG BUILD_IMAGE="python:${DETECTED_PYTHON_VERSION}-slim"
    ARG RUN_IMAGE="python:${DETECTED_PYTHON_VERSION}-slim"
ENDIF

# ========================
# Stage 8: Build Base
# ========================
FROM ${BUILD_IMAGE} AS base

WORKDIR /app

# Set Python environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/root/.local/bin:/root/.cargo/bin:/root/.rye/shims:$PATH"

# Install system dependencies
IF RUN command -v apt-get >/dev/null 2>&1
    RUN apt-get update && \
        apt-get install -y --no-install-recommends \
            gcc g++ make \
            libpq-dev libmariadb-dev libsqlite3-dev \
            libxml2-dev libxslt1-dev \
            libjpeg-dev libpng-dev libfreetype6-dev \
            libssl-dev libffi-dev \
            curl wget git \
            ca-certificates \
            && apt-get clean && rm -rf /var/lib/apt/lists/*
ELSE IF RUN command -v apk >/dev/null 2>&1
    RUN apk add --no-cache \
        gcc g++ make musl-dev linux-headers \
        postgresql-dev mariadb-dev sqlite-dev \
        libxml2-dev libxslt-dev \
        jpeg-dev libpng-dev freetype-dev \
        openssl-dev libffi-dev \
        curl wget git \
        ca-certificates
ENDIF

# Upgrade pip and install build tools
RUN python -m pip install --upgrade pip setuptools wheel

# ========================
# Stage 9: Package Manager Installation
# ========================
FROM base AS pm-installer

COPY --from=package-manager-detector /detect/package_manager.txt /tmp/
PROC cat /tmp/package_manager.txt
ARG PM="${STDOUT}"

# Install package managers
RUN set -e; \
    echo "Installing package manager: ${PM}"; \
    if [ "${PM}" = "poetry" ]; then \
        curl -sSL https://install.python-poetry.org | python3 -; \
    elif [ "${PM}" = "pipenv" ]; then \
        pip install pipenv; \
    elif [ "${PM}" = "uv" ]; then \
        curl -LsSf https://astral.sh/uv/install.sh | sh; \
    elif [ "${PM}" = "pdm" ]; then \
        pip install pdm; \
    elif [ "${PM}" = "hatch" ]; then \
        pip install hatch; \
    elif [ "${PM}" = "rye" ]; then \
        curl -sSf https://rye.astral.sh/get | bash; \
    fi

# ========================
# Stage 10: Dependencies
# ========================
FROM pm-installer AS dependencies

# Copy dependency files (all possible formats)
COPY pyproject.toml setup.py setup.cfg requirements.txt requirements/ \
     poetry.lock Pipfile Pipfile.lock pdm.lock uv.lock rye.lock \
     environment.yml environment.yaml \
     .python-version runtime.txt \
     /app/ 2>/dev/null || true

COPY --from=package-manager-detector /detect/package_manager.txt /tmp/
PROC cat /tmp/package_manager.txt
ARG PM="${STDOUT}"

# Install dependencies with cache mounts
RUN --mount=type=cache,target=/root/.cache/pip \
    --mount=type=cache,target=/root/.cache/pypoetry \
    --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pdm \
    set -e; \
    echo "Installing dependencies with ${PM}..."; \
    \
    if [ "${PM}" = "uv" ]; then \
        if [ -f "uv.lock" ]; then \
            uv sync --frozen --no-dev; \
        elif [ -f "pyproject.toml" ]; then \
            uv pip install --system .; \
        elif [ -f "requirements.txt" ]; then \
            uv pip install --system -r requirements.txt; \
        fi; \
    elif [ "${PM}" = "pdm" ]; then \
        pdm install --prod --no-lock --no-self; \
    elif [ "${PM}" = "poetry" ]; then \
        poetry config virtualenvs.create false; \
        poetry install --only main --no-root --no-interaction; \
    elif [ "${PM}" = "pipenv" ]; then \
        pipenv install --system --deploy --ignore-pipfile; \
    elif [ "${PM}" = "hatch" ]; then \
        pip install -e .; \
    elif [ "${PM}" = "rye" ]; then \
        rye sync --no-dev; \
    elif [ "${PM}" = "conda" ]; then \
        if [ -f "environment.yml" ]; then \
            conda env create -f environment.yml --name app --quiet; \
        elif [ -f "environment.yaml" ]; then \
            conda env create -f environment.yaml --name app --quiet; \
        fi; \
        conda clean --all --yes; \
    elif [ "${PM}" = "pip" ]; then \
        if [ -f "requirements.txt" ]; then \
            pip install -r requirements.txt; \
        elif [ -d "requirements" ]; then \
            find requirements -name "*.txt" -exec pip install -r {} \;; \
        elif [ -f "pyproject.toml" ]; then \
            pip install .; \
        elif [ -f "setup.py" ]; then \
            pip install .; \
        fi; \
    fi

# Install production server
COPY --from=server-detector /detect/server.txt /tmp/
PROC cat /tmp/server.txt
ARG SERVER="${STDOUT}"

RUN set -e; \
    echo "Installing server: ${SERVER}"; \
    if [ "${SERVER}" = "uvicorn" ]; then \
        pip install "uvicorn[standard]" uvloop httptools; \
    elif [ "${SERVER}" = "gunicorn" ]; then \
        pip install gunicorn gevent; \
    elif [ "${SERVER}" = "hypercorn" ]; then \
        pip install hypercorn; \
    elif [ "${SERVER}" = "daphne" ]; then \
        pip install daphne; \
    elif [ "${SERVER}" = "granian" ]; then \
        pip install granian; \
    elif [ "${SERVER}" = "waitress" ]; then \
        pip install waitress; \
    elif [ "${SERVER}" = "uwsgi" ]; then \
        pip install uwsgi; \
    fi

# ========================
# Stage 11: Builder
# ========================
FROM dependencies AS builder

# Copy application code
COPY . .

COPY --from=framework-detector /detect/framework.txt /tmp/
PROC cat /tmp/framework.txt
ARG FRAMEWORK="${STDOUT}"

# Framework-specific build steps
IF RUN [ "${FRAMEWORK}" = "django" ]
    RUN python manage.py collectstatic --noinput 2>/dev/null || \
        echo "⚠️  No static files to collect"
ENDIF

IF RUN [ -f "setup.py" ] || [ -f "pyproject.toml" ]
    RUN pip install -e . 2>/dev/null || true
ENDIF

# ========================
# Stage 12: Runtime Image
# ========================
FROM ${RUN_IMAGE} AS runtime

WORKDIR /app

# Create non-root user
RUN if command -v useradd >/dev/null 2>&1; then \
        groupadd -r app && \
        useradd -r -g app -d /app -s /bin/bash app; \
    else \
        addgroup -S app && \
        adduser -S -D -h /app -s /bin/bash -G app app; \
    fi && \
    chown -R app:app /app

# Set environment
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/home/app/.local/bin:$PATH" \
    PORT=8000

# Copy Python installation
COPY --from=builder --chown=app:app /usr/local/lib/python*/site-packages /usr/local/lib/python*/site-packages
COPY --from=builder --chown=app:app /usr/local/bin /usr/local/bin
COPY --from=builder --chown=app:app /app /app

# Framework-specific directories
COPY --from=framework-detector /detect/framework.txt /tmp/
PROC cat /tmp/framework.txt
ARG FRAMEWORK="${STDOUT}"

IF RUN [ "${FRAMEWORK}" = "django" ]
    RUN mkdir -p /app/staticfiles /app/media && \
        chown -R app:app /app/staticfiles /app/media
ENDIF

USER app

EXPOSE 8000

# ========================
# Stage 13: Production
# ========================
FROM runtime AS production

# Create intelligent entrypoint
RUN cat > /app/entrypoint.sh <<'ENTRYPOINT'
#!/bin/bash
set -euo pipefail

# Read detection results
FRAMEWORK=$(cat /tmp/framework.txt 2>/dev/null || echo "generic")
SERVER=$(cat /tmp/server.txt 2>/dev/null || echo "uvicorn")

# Environment variables
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
WORKERS="${WORKERS:-$(nproc)}"

echo "🐍 Python Application Startup"
echo "Framework: $FRAMEWORK"
echo "Server: $SERVER"
echo "Workers: $WORKERS"

# Handle CLI commands
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# Determine application module
if [ "$FRAMEWORK" = "django" ]; then
    if [ -f "manage.py" ]; then
        WSGI_MODULE=$(python -c "import os; print(os.environ.get('DJANGO_SETTINGS_MODULE', 'config.settings').rsplit('.', 1)[0] + '.wsgi:application')" 2>/dev/null || echo "config.wsgi:application")
        APP_MODULE="$WSGI_MODULE"
    else
        echo "❌ Django detected but no manage.py found"
        exit 1
    fi
else
    # Try to find app module
    if [ -f "main.py" ]; then
        APP_MODULE="main:app"
    elif [ -f "app.py" ]; then
        APP_MODULE="app:app"
    elif [ -f "asgi.py" ]; then
        APP_MODULE="asgi:application"
    elif [ -f "wsgi.py" ]; then
        APP_MODULE="wsgi:application"
    else
        echo "⚠️  Could not auto-detect app module, using main:app"
        APP_MODULE="main:app"
    fi
fi

echo "App module: $APP_MODULE"

# Start server
case "$SERVER" in
    uvicorn)
        exec uvicorn "$APP_MODULE" \
            --host "$HOST" \
            --port "$PORT" \
            --workers "$WORKERS" \
            --loop uvloop \
            --http httptools
        ;;
    gunicorn)
        if [ "$FRAMEWORK" = "fastapi" ] || [ "$FRAMEWORK" = "litestar" ]; then
            WORKER_CLASS="uvicorn.workers.UvicornWorker"
        else
            WORKER_CLASS="gevent"
        fi
        exec gunicorn "$APP_MODULE" \
            --bind "$HOST:$PORT" \
            --workers "$WORKERS" \
            --worker-class "$WORKER_CLASS" \
            --timeout 120 \
            --access-logfile - \
            --error-logfile -
        ;;
    hypercorn)
        exec hypercorn "$APP_MODULE" \
            --bind "$HOST:$PORT" \
            --workers "$WORKERS"
        ;;
    daphne)
        exec daphne \
            -b "$HOST" \
            -p "$PORT" \
            "$APP_MODULE"
        ;;
    granian)
        exec granian \
            --host "$HOST" \
            --port "$PORT" \
            --workers "$WORKERS" \
            --interface asgi \
            "$APP_MODULE"
        ;;
    waitress)
        exec waitress-serve \
            --host="$HOST" \
            --port="$PORT" \
            "$APP_MODULE"
        ;;
    sanic)
        exec python -m sanic "$APP_MODULE" \
            --host="$HOST" \
            --port="$PORT" \
            --workers="$WORKERS"
        ;;
    *)
        echo "⚠️  Unknown server, trying to run main.py"
        if [ -f "main.py" ]; then
            exec python main.py
        else
            echo "❌ No entrypoint found"
            exit 1
        fi
        ;;
esac
ENTRYPOINT

RUN chmod +x /app/entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${PORT}/health')" || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
CMD []

# ========================
# Stage 14: Release
# ========================
FROM production AS release

LABEL org.opencontainers.image.title="Universal Python Application" \
      org.opencontainers.image.description="Auto-detecting Python framework container" \
      org.opencontainers.image.vendor="Dexnore" \
      com.dexnore.auto-detect="true" \
      com.dexnore.supports="django,fastapi,flask,litestar,generic"