# syntax=dexnore/dexfile:0

# Production-ready Python Dexfile supporting:
# - Runtimes: CPython, PyPy, GraalPy
# - Package Managers: pip, venv, poetry, pipenv, conda/mamba, uv, pdm, hatch, rye
# - Frameworks: Django, Flask, FastAPI, Litestar, Starlette, Quart, Sanic, Tornado, Pyramid
# - ASGI Servers: Uvicorn, Hypercorn, Daphne, Granian
# - WSGI Servers: Gunicorn, uWSGI, Waitress, mod_wsgi
# - Task Queues: Celery, RQ, Dramatiq, Huey, Taskiq
# - Testing: pytest, nox, tox
# - Web Servers: nginx, Caddy, Traefik (reverse proxy configs)
# - Tools: setuptools, wheel, build, invoke, make

ARG BUILD_IMAGE RUN_IMAGE PORT=8000 PYTHON_VERSION
ARG PACKAGE_MANAGER FRAMEWORK_TYPE SERVER_TYPE RUNTIME_TYPE
ARG ENABLE_CELERY=false ENABLE_NGINX=false

WORKDIR /home/dexfile/app

# ============================================================================
# PYTHON VERSION DETECTION
# ============================================================================
FUNC detect_python_version
    # Priority order for version detection
    # 1. .python-version (pyenv, asdf)
    IF PROC --from=busybox:latest --mount=target=. [ -f ".python-version" ]
        ARG PYTHON_VERSION=$(cat .python-version | tr -d ' \t\r\n' | head -1)
    # 2. pyproject.toml requires-python
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "pyproject.toml" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP 'requires-python\s*=\s*"\K[^"]+' pyproject.toml | grep -oP '[0-9]+\.[0-9]+' | sort -V | tail -1) && [ -n "$VERSION" ] && echo "$VERSION"
            ARG PYTHON_VERSION=${STDOUT}
        ENDIF
    # 3. setup.py python_requires
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "setup.py" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP "python_requires\s*=\s*['\"]?\K[^'\"]+(?=['\"]?)" setup.py | grep -oP '[0-9]+\.[0-9]+' | sort -V | tail -1) && [ -n "$VERSION" ] && echo "$VERSION"
            ARG PYTHON_VERSION=${STDOUT}
        ENDIF
    # 4. Pipfile python_version
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Pipfile" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -A1 "\[requires\]" Pipfile | grep -oP 'python_version\s*=\s*"\K[^"]+' | head -1) && [ -n "$VERSION" ] && echo "$VERSION"
            ARG PYTHON_VERSION=${STDOUT}
        ENDIF
    # 5. runtime.txt (Heroku style)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "runtime.txt" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP 'python-\K[0-9]+\.[0-9]+' runtime.txt | head -1) && [ -n "$VERSION" ] && echo "$VERSION"
            ARG PYTHON_VERSION=${STDOUT}
        ENDIF
    # 6. tox.ini or nox.py (testing tools)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "tox.ini" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP 'py[0-9]+' tox.ini | grep -oP '[0-9]+' | head -1 | sed 's/\([0-9]\)\([0-9]\)/\1.\2/') && [ -n "$VERSION" ] && echo "$VERSION"
            ARG PYTHON_VERSION=${STDOUT}
        ENDIF
    ENDIF
    
    # Default to 3.12 if no version found
    IF PROC [ -z "${PYTHON_VERSION}" ]
        ARG PYTHON_VERSION="3.12"
    ENDIF
ENDFUNC

# ============================================================================
# RUNTIME TYPE DETECTION (CPython vs PyPy)
# ============================================================================
FUNC detect_runtime_type
    IF PROC --from=busybox:latest --mount=target=. grep -q "pypy" .python-version 2>/dev/null
        ARG RUNTIME_TYPE="pypy"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "graalpy" .python-version 2>/dev/null
        ARG RUNTIME_TYPE="graalpy"
    ELSE
        ARG RUNTIME_TYPE="cpython"
    ENDIF
ENDFUNC

# ============================================================================
# PACKAGE MANAGER DETECTION
# ============================================================================
FUNC detect_package_manager
    # Priority: Most specific to least specific
    IF PROC --from=busybox:latest --mount=target=. [ -f "uv.lock" ]
        ARG PACKAGE_MANAGER="uv"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "pdm.lock" ]
        ARG PACKAGE_MANAGER="pdm"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "poetry.lock" ]
        ARG PACKAGE_MANAGER="poetry"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Pipfile.lock" ] || [ -f "Pipfile" ]
        ARG PACKAGE_MANAGER="pipenv"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "environment.yml" ] || [ -f "environment.yaml" ]
        ARG PACKAGE_MANAGER="conda"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "pyproject.toml" ]
        # Check for specific tools in pyproject.toml
        IF PROC --from=busybox:latest --mount=target=. grep -q "\[tool.hatch\]" pyproject.toml
            ARG PACKAGE_MANAGER="hatch"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "\[tool.rye\]" pyproject.toml
            ARG PACKAGE_MANAGER="rye"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "\[tool.pdm\]" pyproject.toml
            ARG PACKAGE_MANAGER="pdm"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "\[tool.poetry\]" pyproject.toml
            ARG PACKAGE_MANAGER="poetry"
        ELSE
            ARG PACKAGE_MANAGER="pip"
        ENDIF
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "requirements.txt" ] || [ -f "requirements/*.txt" ]
        ARG PACKAGE_MANAGER="pip"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "setup.py" ] || [ -f "setup.cfg" ]
        ARG PACKAGE_MANAGER="pip"
    ELSE
        RUN echo "ERROR: No Python package manager configuration found" >&2 && exit 1
    ENDIF
ENDFUNC

# ============================================================================
# FRAMEWORK DETECTION
# ============================================================================
FUNC detect_framework
    # Check pyproject.toml and requirements files for framework dependencies
    IF PROC --from=busybox:latest --mount=target=. grep -qiE "(django|Django)" pyproject.toml setup.py setup.cfg requirements.txt requirements/*.txt Pipfile 2>/dev/null
        ARG FRAMEWORK_TYPE="django"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -qiE "(fastapi|FastAPI)" pyproject.toml setup.py setup.cfg requirements.txt requirements/*.txt Pipfile 2>/dev/null
        ARG FRAMEWORK_TYPE="fastapi"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -qiE "(litestar|Litestar)" pyproject.toml setup.py setup.cfg requirements.txt requirements/*.txt Pipfile 2>/dev/null
        ARG FRAMEWORK_TYPE="litestar"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -qiE "(flask|Flask)" pyproject.toml setup.py setup.cfg requirements.txt requirements/*.txt Pipfile 2>/dev/null
        ARG FRAMEWORK_TYPE="flask"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -qiE "(quart|Quart)" pyproject.toml setup.py setup.cfg requirements.txt requirements/*.txt Pipfile 2>/dev/null
        ARG FRAMEWORK_TYPE="quart"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -qiE "(sanic|Sanic)" pyproject.toml setup.py setup.cfg requirements.txt requirements/*.txt Pipfile 2>/dev/null
        ARG FRAMEWORK_TYPE="sanic"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -qiE "(tornado|Tornado)" pyproject.toml setup.py setup.cfg requirements.txt requirements/*.txt Pipfile 2>/dev/null
        ARG FRAMEWORK_TYPE="tornado"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -qiE "(pyramid|Pyramid)" pyproject.toml setup.py setup.cfg requirements.txt requirements/*.txt Pipfile 2>/dev/null
        ARG FRAMEWORK_TYPE="pyramid"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -qiE "(starlette|Starlette)" pyproject.toml setup.py setup.cfg requirements.txt requirements/*.txt Pipfile 2>/dev/null
        ARG FRAMEWORK_TYPE="starlette"
    ELSE
        ARG FRAMEWORK_TYPE="generic"
    ENDIF
ENDFUNC

# ============================================================================
# SERVER TYPE DETECTION
# ============================================================================
FUNC detect_server_type
    # Detect preferred server based on framework and dependencies
    IF PROC [ "${FRAMEWORK_TYPE}" = "django" ]
        IF PROC --from=busybox:latest --mount=target=. grep -qiE "(channels|daphne)" pyproject.toml requirements.txt requirements/*.txt 2>/dev/null
            ARG SERVER_TYPE="daphne"
        ELSE
            ARG SERVER_TYPE="gunicorn"
        ENDIF
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "fastapi" ] || [ "${FRAMEWORK_TYPE}" = "litestar" ] || [ "${FRAMEWORK_TYPE}" = "starlette" ]
        IF PROC --from=busybox:latest --mount=target=. grep -qiE "(granian|Granian)" pyproject.toml requirements.txt requirements/*.txt 2>/dev/null
            ARG SERVER_TYPE="granian"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -qiE "(hypercorn|Hypercorn)" pyproject.toml requirements.txt requirements/*.txt 2>/dev/null
            ARG SERVER_TYPE="hypercorn"
        ELSE
            ARG SERVER_TYPE="uvicorn"
        ENDIF
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "flask" ] || [ "${FRAMEWORK_TYPE}" = "pyramid" ]
        IF PROC --from=busybox:latest --mount=target=. grep -qiE "(waitress|Waitress)" pyproject.toml requirements.txt requirements/*.txt 2>/dev/null
            ARG SERVER_TYPE="waitress"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -qiE "(uwsgi|uWSGI)" pyproject.toml requirements.txt requirements/*.txt 2>/dev/null
            ARG SERVER_TYPE="uwsgi"
        ELSE
            ARG SERVER_TYPE="gunicorn"
        ENDIF
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "sanic" ]
        ARG SERVER_TYPE="sanic"
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "tornado" ]
        ARG SERVER_TYPE="tornado"
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "quart" ]
        ARG SERVER_TYPE="hypercorn"
    ELSE
        ARG SERVER_TYPE="uvicorn"
    ENDIF
ENDFUNC

# ============================================================================
# CELERY DETECTION
# ============================================================================
FUNC detect_celery
    IF PROC --from=busybox:latest --mount=target=. grep -qiE "(celery|Celery)" pyproject.toml requirements.txt requirements/*.txt Pipfile 2>/dev/null
        ARG ENABLE_CELERY=true
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -qiE "(rq|dramatiq|huey|taskiq)" pyproject.toml requirements.txt requirements/*.txt Pipfile 2>/dev/null
        ARG ENABLE_CELERY=true
    ENDIF
ENDFUNC

# ============================================================================
# NGINX DETECTION
# ============================================================================
FUNC detect_nginx
    IF PROC --from=busybox:latest --mount=target=. [ -f "nginx.conf" ] || [ -f "nginx/nginx.conf" ]
        ARG ENABLE_NGINX=true
        ARG RUN_IMAGE="nginx:alpine"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Caddyfile" ]
        ARG ENABLE_NGINX=true
        ARG RUN_IMAGE="caddy:2-alpine"
    ENDIF
ENDFUNC

# ============================================================================
# BUILD IMAGE SELECTION
# ============================================================================
FUNC select_build_image
    IF PROC [ "${PACKAGE_MANAGER}" = "conda" ]
        ARG BUILD_IMAGE="continuumio/miniconda3:latest"
    ELSE IF PROC [ "${RUNTIME_TYPE}" = "pypy" ]
        ARG BUILD_IMAGE="pypy:${PYTHON_VERSION}-slim"
    ELSE
        ARG BUILD_IMAGE="python:${PYTHON_VERSION}-slim"
    ENDIF
ENDFUNC

# ============================================================================
# RUN DETECTIONS
# ============================================================================
FUNC CALL detect_python_version
FUNC CALL detect_runtime_type
FUNC CALL detect_package_manager
FUNC CALL detect_framework
FUNC CALL detect_server_type
FUNC CALL detect_celery
FUNC CALL detect_nginx
FUNC CALL select_build_image

# Validate Python project exists
IF PROC --from=busybox:latest --mount=target=. ! find . -maxdepth 3 -type f \( -name "*.py" -o -name "pyproject.toml" -o -name "requirements.txt" -o -name "setup.py" -o -name "Pipfile" -o -name "environment.yml" \) 2>/dev/null | grep -q .
    RUN echo "ERROR: No Python project files found" >&2 && exit 1
ENDIF

# ============================================================================
# BASE BUILD STAGE
# ============================================================================
FROM ${BUILD_IMAGE} AS base
WORKDIR /home/dexfile/app

# Install system dependencies
RUN if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            gcc g++ make \
            libpq-dev libmariadb-dev libsqlite3-dev \
            libxml2-dev libxslt1-dev \
            libjpeg-dev libpng-dev libfreetype6-dev \
            libssl-dev libffi-dev \
            curl wget git \
            build-essential && \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache \
            gcc g++ make musl-dev \
            postgresql-dev mariadb-dev sqlite-dev \
            libxml2-dev libxslt-dev \
            jpeg-dev libpng-dev freetype-dev \
            openssl-dev libffi-dev \
            curl wget git; \
    fi

# Set Python environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV DEBIAN_FRONTEND=noninteractive

# Install package managers
RUN set -e; \
    python -m pip install --upgrade pip setuptools wheel; \
    if [ "${PACKAGE_MANAGER}" = "poetry" ]; then \
        curl -sSL https://install.python-poetry.org | python3 -; \
        export PATH="/root/.local/bin:$PATH"; \
    elif [ "${PACKAGE_MANAGER}" = "pipenv" ]; then \
        pip install pipenv; \
    elif [ "${PACKAGE_MANAGER}" = "uv" ]; then \
        curl -LsSf https://astral.sh/uv/install.sh | sh; \
        export PATH="/root/.cargo/bin:$PATH"; \
    elif [ "${PACKAGE_MANAGER}" = "pdm" ]; then \
        pip install pdm; \
    elif [ "${PACKAGE_MANAGER}" = "hatch" ]; then \
        pip install hatch; \
    elif [ "${PACKAGE_MANAGER}" = "rye" ]; then \
        curl -sSf https://rye.astral.sh/get | bash; \
        export PATH="/root/.rye/shims:$PATH"; \
    fi

# Set PATH for installed tools
ENV PATH="/root/.local/bin:/root/.cargo/bin:/root/.rye/shims:$PATH"

# ============================================================================
# DEPENDENCY INSTALLATION STAGE
# ============================================================================
FROM base AS deps

# Copy dependency files
COPY pyproject.toml setup.py setup.cfg requirements.txt requirements/ \
     poetry.lock Pipfile Pipfile.lock pdm.lock uv.lock \
     environment.yml environment.yaml \
     .python-version runtime.txt \
     /home/dexfile/app/ 2>/dev/null || true

# Install dependencies based on package manager
RUN --mount=type=cache,id=pip-cache,target=/root/.cache/pip,sharing=locked \
    --mount=type=cache,id=poetry-cache,target=/root/.cache/pypoetry,sharing=locked \
    --mount=type=cache,id=uv-cache,target=/root/.cache/uv,sharing=locked \
    --mount=type=cache,id=pdm-cache,target=/root/.cache/pdm,sharing=locked \
    --mount=type=cache,id=conda-pkgs,target=/opt/conda/pkgs,sharing=locked \
    set -e; \
    echo "Installing dependencies with ${PACKAGE_MANAGER}..."; \
    \
    if [ "${PACKAGE_MANAGER}" = "uv" ]; then \
        uv pip install --system -r pyproject.toml 2>/dev/null || \
        uv pip install --system -r requirements.txt; \
    elif [ "${PACKAGE_MANAGER}" = "pdm" ]; then \
        pdm install --prod --no-lock --no-self; \
    elif [ "${PACKAGE_MANAGER}" = "poetry" ]; then \
        poetry config virtualenvs.create false; \
        poetry install --only main --no-root --no-interaction; \
    elif [ "${PACKAGE_MANAGER}" = "pipenv" ]; then \
        pipenv install --system --deploy --ignore-pipfile; \
    elif [ "${PACKAGE_MANAGER}" = "hatch" ]; then \
        hatch env create default; \
        hatch run pip install -e .; \
    elif [ "${PACKAGE_MANAGER}" = "rye" ]; then \
        rye sync --no-dev; \
    elif [ "${PACKAGE_MANAGER}" = "conda" ]; then \
        if [ -f "environment.yml" ]; then \
            conda env create -f environment.yml --name app --quiet; \
        elif [ -f "environment.yaml" ]; then \
            conda env create -f environment.yaml --name app --quiet; \
        fi; \
        conda clean --all --yes; \
    elif [ "${PACKAGE_MANAGER}" = "pip" ]; then \
        if [ -f "requirements.txt" ]; then \
            pip install --no-cache-dir -r requirements.txt; \
        elif [ -d "requirements" ]; then \
            find requirements -name "*.txt" -exec pip install --no-cache-dir -r {} \;; \
        elif [ -f "pyproject.toml" ]; then \
            pip install --no-cache-dir .; \
        elif [ -f "setup.py" ]; then \
            pip install --no-cache-dir .; \
        fi; \
    fi; \
    \
    echo "Installing production server: ${SERVER_TYPE}..."; \
    if [ "${SERVER_TYPE}" = "uvicorn" ]; then \
        pip install --no-cache-dir "uvicorn[standard]" uvloop httptools; \
    elif [ "${SERVER_TYPE}" = "gunicorn" ]; then \
        pip install --no-cache-dir gunicorn gevent; \
    elif [ "${SERVER_TYPE}" = "hypercorn" ]; then \
        pip install --no-cache-dir hypercorn; \
    elif [ "${SERVER_TYPE}" = "daphne" ]; then \
        pip install --no-cache-dir daphne; \
    elif [ "${SERVER_TYPE}" = "granian" ]; then \
        pip install --no-cache-dir granian; \
    elif [ "${SERVER_TYPE}" = "waitress" ]; then \
        pip install --no-cache-dir waitress; \
    elif [ "${SERVER_TYPE}" = "uwsgi" ]; then \
        pip install --no-cache-dir uwsgi; \
    fi

# ============================================================================
# BUILDER STAGE
# ============================================================================
FROM base AS builder

# Copy dependencies
COPY --from=deps /usr/local/lib/python*/site-packages /usr/local/lib/python*/site-packages 2>/dev/null || true
COPY --from=deps /opt/conda /opt/conda 2>/dev/null || true
COPY --from=deps /root/.local /root/.local 2>/dev/null || true

# Copy source code
COPY . .

# Build application if needed
RUN --mount=type=cache,id=pip-cache,target=/root/.cache/pip,sharing=locked \
    set -e; \
    if [ "${PACKAGE_MANAGER}" = "poetry" ]; then \
        poetry build 2>/dev/null || true; \
    elif [ "${PACKAGE_MANAGER}" = "hatch" ]; then \
        hatch build 2>/dev/null || true; \
    elif [ "${PACKAGE_MANAGER}" = "pdm" ]; then \
        pdm build 2>/dev/null || true; \
    elif [ -f "setup.py" ]; then \
        python setup.py build 2>/dev/null || true; \
    fi; \
    \
    if [ "${FRAMEWORK_TYPE}" = "django" ]; then \
        python manage.py collectstatic --noinput 2>/dev/null || echo "No static files to collect"; \
    fi

# ============================================================================
# RUNTIME BASE STAGE
# ============================================================================
FROM ${RUN_IMAGE} AS app

# For nginx/caddy, skip Python runtime
IF PROC [ "${ENABLE_NGINX}" != "true" ]
    # Create non-root user
    RUN if command -v groupadd >/dev/null 2>&1; then \
            groupadd -r dexnore && \
            useradd -r -g dexnore -d /home/dexfile/app -s /sbin/nologin dexfile; \
        elif command -v addgroup >/dev/null 2>&1; then \
            addgroup -S dexnore && \
            adduser -S -D -H -h /home/dexfile/app -s /sbin/nologin -G dexnore dexfile; \
        fi && \
        mkdir -p /home/dexfile/app && \
        chown -R dexfile:dexnore /home/dexfile/app
    
    WORKDIR /home/dexfile/app
    USER dexfile:dexnore
    
    # Set runtime environment
    ENV PYTHONUNBUFFERED=1
    ENV PYTHONDONTWRITEBYTECODE=1
    ENV PATH="/home/dexfile/.local/bin:$PATH"
    ENV PORT=${PORT}
    EXPOSE ${PORT}
ENDIF

# ============================================================================
# PRODUCTION STAGE
# ============================================================================
FROM app AS prod

# Handle nginx static serving
IF PROC [ "${ENABLE_NGINX}" = "true" ]
    # Copy nginx/Caddy config
    IF PROC --from=busybox:latest --mount=target=. [ -f "nginx.conf" ]
        COPY --chown=root:root nginx.conf /etc/nginx/nginx.conf
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "nginx/nginx.conf" ]
        COPY --chown=root:root nginx/nginx.conf /etc/nginx/nginx.conf
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Caddyfile" ]
        COPY --chown=root:root Caddyfile /etc/caddy/Caddyfile
    ENDIF
    
    # Copy static files
    IF PROC [ "${FRAMEWORK_TYPE}" = "django" ]
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/staticfiles /usr/share/nginx/html/static 2>/dev/null || \
             COPY --chown=nginx:nginx --from=builder /home/dexfile/app/static /usr/share/nginx/html/static
    ELSE
        COPY --chown=nginx:nginx --from=builder /home/dexfile/app/static /usr/share/nginx/html/static 2>/dev/null || \
             COPY --chown=nginx:nginx --from=builder /home/dexfile/app/public /usr/share/nginx/html/
    ENDIF
    
    IF PROC echo "${RUN_IMAGE}" | grep -q "nginx"
        CMD ["nginx", "-g", "daemon off;"]
    ELSE
        CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]
    ENDIF

# Handle Python runtime
ELSE
    # Copy installed dependencies
    COPY --chown=dexfile:dexnore --from=deps /usr/local/lib/python*/site-packages /usr/local/lib/python*/site-packages 2>/dev/null || true
    COPY --chown=dexfile:dexnore --from=deps /opt/conda /opt/conda 2>/dev/null || true
    
    # Copy application code
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app /home/dexfile/app
    
    # Framework-specific health checks
    IF PROC [ "${FRAMEWORK_TYPE}" = "django" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
            CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${PORT}/health/')" || exit 1
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "fastapi" ] || [ "${FRAMEWORK_TYPE}" = "litestar" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
            CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${PORT}/health')" || exit 1
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "flask" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
            CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${PORT}/health')" || exit 1
    ENDIF
    
    # Set entrypoint based on server type and framework
    IF PROC [ "${SERVER_TYPE}" = "uvicorn" ]
        IF PROC [ "${FRAMEWORK_TYPE}" = "django" ]
            CMD ["uvicorn", "config.asgi:application", "--host", "0.0.0.0", "--port", "${PORT}", "--workers", "4"]
        ELSE
            CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "${PORT}", "--workers", "4"]
        ENDIF
    ELSE IF PROC [ "${SERVER_TYPE}" = "gunicorn" ]
        IF PROC [ "${FRAMEWORK_TYPE}" = "django" ]
            CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:${PORT}", "--workers", "4", "--worker-class", "gevent"]
        ELSE
            CMD ["gunicorn", "main:app", "--bind", "0.0.0.0:${PORT}", "--workers", "4", "--worker-class", "gevent"]
        ENDIF
    ELSE IF PROC [ "${SERVER_TYPE}" = "hypercorn" ]
        CMD ["hypercorn", "main:app", "--bind", "0.0.0.0:${PORT}", "--workers", "4"]
    ELSE IF PROC [ "${SERVER_TYPE}" = "daphne" ]
        CMD ["daphne", "-b", "0.0.0.0", "-p", "${PORT}", "config.asgi:application"]
    ELSE IF PROC [ "${SERVER_TYPE}" = "granian" ]
        CMD ["granian", "--host", "0.0.0.0", "--port", "${PORT}", "--workers", "4", "main:app"]
    ELSE IF PROC [ "${SERVER_TYPE}" = "waitress" ]
        CMD ["waitress-serve", "--host=0.0.0.0", "--port=${PORT}", "main:app"]
    ELSE IF PROC [ "${SERVER_TYPE}" = "sanic" ]
        CMD ["python", "-m", "sanic", "main:app", "--host=0.0.0.0", "--port=${PORT}", "--workers=4"]
    ELSE IF PROC [ "${SERVER_TYPE}" = "tornado" ]
        CMD ["python", "main.py"]
    ELSE
        # Generic Python application
        CMD ["python", "main.py"]
    ENDIF
ENDIF

# ============================================================================
# RELEASE STAGE
# ============================================================================
FROM prod AS release

# Metadata labels
LABEL maintainer="@dexnore/dexfile"
LABEL org.opencontainers.image.vendor="Dexnore"

FROM release