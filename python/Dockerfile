# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

ARG BUILD_IMAGE RUN_IMAGE
WORKDIR /home/dexfile/app
PROC --mount=target=. find . -type f 2>/dev/null | grep -m1 \
    -e 'requirements' \
    -e 'poetry.lock' \
    -e 'Pipfile.lock' \
    -e 'pdm.lock' \
    -e 'uv.lock' \
    -e 'environment.yml' \
    -e 'environment.yaml' \
    -e 'pyproject.toml' \
    -e 'setup.py' \
    -e 'setup.cfg' \
    >/dev/null; then \
        echo "Python project detected"; \
    else \
        echo "Not a python project" >&2; \
        exit 1; \
    fi

IF PROC --mount=target=. if [ -n "${BUILD_IMAGE}" ]; then \
        echo "BUILD_IMAGE is already set — refusing to auto-detect Python version." >&2; \
        exit 1; \
    fi; \
    PYTHON_IMAGE_SUFFIX="${PYTHON_IMAGE_SUFFIX:-"-slim"}"; \
    VERSIONS=""; \
    for FILE in $(find . -type f \( \
        -name ".python-version" -o \
        -name "pyproject.toml" -o \
        -name "setup.py" -o \
        -name "Pipfile" \
    \) 2>/dev/null); do \
        case "$FILE" in \
            *.python-version) \
                PYTHON_VERSION=$(cat "$FILE" | tr -d ' \t\r'); \
                ;; \
            *pyproject.toml) \
                RAW=$(grep -E "requires-python" "$FILE" 2>/dev/null || true); \
                PYTHON_VERSION=$(echo "$RAW" | sed 's/.*=//g' | tr -d '" ' | \
                    tr ',' '\n' | grep -Eo '[0-9]+\.[0-9]+' | sort -V | tail -n 1); \
                ;; \
            *setup.py) \
                RAW=$(grep -E "python_requires" "$FILE" 2>/dev/null || true); \
                PYTHON_VERSION=$(echo "$RAW" | sed 's/.*=//g' | tr -d '" ,' | \
                    tr ',' '\n' | grep -Eo '[0-9]+\.[0-9]+' | sort -V | tail -n 1); \
                ;; \
            *Pipfile) \
                RAW=$(grep -A1 "\[requires\]" "$FILE" 2>/dev/null | grep "python_version" || true); \
                PYTHON_VERSION=$(echo "$RAW" | sed 's/.*=//g' | tr -d '" ' | \
                    tr ',' '\n' | grep -Eo '[0-9]+\.[0-9]+' | sort -V | tail -n 1); \
                ;; \
        esac; \
        [ -n "$PYTHON_VERSION" ] && VERSIONS="$VERSIONS $PYTHON_VERSION"; \
    done; \
    CLEANED=$(echo "$VERSIONS" | sed 's/[<>=!~]//g'); \
    REQUIRED=$(echo "$CLEANED" | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+' | sort -V | tail -n 1); \
    if [ -n "$REQUIRED" ]; then \
        echo "${REQUIRED}${PYTHON_IMAGE_SUFFIX}"; \
    else \
        echo "No valid Python version found in project files." >&2; \
        exit 1; \
    fi

    ARG BUILD_IMAGE=python:${STDOUT:-latest}
    IF PROC [ -z "${RUN_IMAGE}" ]
        ARG RUN_IMAGE=${BUILD_IMAGE}
    ENDIF
ENDIF

IF PROC --mount=target=. [ -f "environment.yml" ]
    ARG BUILD_IMAGE=continuumio/miniconda3
ENDIF

# ========================
# Stage 1: Base image
# ========================
FROM ${BUILD_IMAGE:-python:3.12-slim} AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    PATH=/opt/conda/envs/app/bin:$PATH:$HOME/.local/bin

WORKDIR /home/dexfile/app

# Install system dependencies + Python tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc curl && \
    pip install --upgrade pip && \
    pip install pipenv uv && \
    curl -sSL https://install.python-poetry.org | python3 - && \
    rm -rf /var/lib/apt/lists/*

# ========================
# Stage 2: Dependency caching
# ========================
FROM base AS deps

# Copy only dependency definition files for caching
COPY pyproject.toml poetry.lock* Pipfile* Pipfile.lock* \
     uv.lock* requirements.txt* environment.yml* environment.yaml* setup.py* setup.cfg* /home/dexfile/app/

# Build wheels / install dependencies  // ~/.cache/pip
RUN --mount=type=cache,target=wheels \
    set -eux; \
    echo ">>> Starting dependency resolution and wheel build"; \
    mkdir -p wheels; \
    \
    # --- Conda Environment ---
    if [ -f environment.yml ]; then \
        echo "Detected Conda environment.yml..."; \
        conda env create -f environment.yml --quiet; \
        conda clean --all --yes; \
    elif [ -f environment.yaml ]; then \
        echo "Detected Conda environment.yaml..."; \
        conda env create -f environment.yaml --quiet; \
        conda clean --all --yes; \
    \
    # --- Pipenv ---
    elif [ -f Pipfile ] && [ -f Pipfile.lock ]; then \
        echo "Detected Pipenv..."; \
        pipenv install --deploy --system; \
        echo "Building wheels for installed packages..."; \
        pip freeze | grep -v "^-e" > /tmp/requirements.installed.txt; \
        pip wheel --no-cache-dir --no-deps --wheel-dir wheels -r /tmp/requirements.installed.txt; \
    \
    # --- Poetry ---
    elif [ -f poetry.lock ] && [ -f pyproject.toml ]; then \
        echo "Detected Poetry..."; \
        if command -v poetry >/dev/null 2>&1; then \
            poetry config virtualenvs.create false; \
            poetry install --no-root; \
            poetry build -f wheel; \
            cp dist/*.whl wheels/; \
            echo "Building wheels for installed packages..."; \
            pip freeze | grep -v "^-e" > /tmp/requirements.installed.txt; \
            pip wheel --no-cache-dir --no-deps --wheel-dir wheels -r /tmp/requirements.installed.txt; \
        else \
            echo "Error: poetry not installed or not in PATH." >&2; \
            exit 1; \
        fi; \
    \
    # --- UV ---
    elif [ -f uv.lock ]; then \
        echo "Detected UV..."; \
        uv install; \
        echo "Building wheels for installed packages..."; \
        pip freeze | grep -v "^-e" > /tmp/requirements.installed.txt; \
        pip wheel --no-cache-dir --no-deps --wheel-dir wheels -r /tmp/requirements.installed.txt; \
    \
    # --- Plain Requirements.txt ---
    elif [ -f requirements.txt ]; then \
        echo "Detected requirements.txt..."; \
        pip wheel --no-cache-dir --no-deps --wheel-dir wheels -r requirements.txt; \
    \
    # --- No recognized dependency file ---
    else \
        echo "No recognized dependency file found (expected environment.yml, Pipfile, poetry.lock, uv.lock, or requirements.txt)." >&2; \
        exit 1; \
    fi; \
    echo ">>> Wheel build completed and cached successfully."

# ========================
# Stage 3: Installer (final runtime)
# ========================
FROM ${BUILD_IMAGE:-python:3.12-slim} AS installer
WORKDIR /home/dexfile/app

# Copy wheels + dependency files
COPY --from=deps /home/dexfile/app/wheels /home/dexfile/app/wheels
COPY --from=deps pyproject.toml setup.py setup.cfg requirements.txt* uv.lock* \
     environment.yml* environment.yaml* /home/dexfile/app/

# Install dependencies from wheels (cached)
RUN set -eux; \
    if [ -f environment.yml ] || [ -f environment.yaml ]; then \
        echo "Conda environment already installed"; \
    elif [ -d wheels ] && [ "$(ls -A wheels)" ]; then \
        pip install --no-cache-dir wheels/*; \
    elif [ -f pyproject.toml ]; then \
        pip install --no-cache-dir .; \
    else \
        echo "Nothing to install"; exit 1; \
    fi

# ========================
# Stage 4: Builder (copy source)
# ========================
FROM installer AS builder
# Only copy application source code to leverage dependency caching
COPY . .

# ========================
# Stage 5: Prod image (FIXED)
# ========================
FROM installer AS prod

RUN groupadd -r dexnore && useradd -r -g dexnore dexfile
WORKDIR /home/dexfile/app
USER dexfile:dexnore

COPY --from=builder /home/dexfile/app /home/dexfile/app

# ------------------------
# Create python-entrypoint.py dynamically (full script)
# ------------------------
RUN mkdir -p /usr/local/bin
COPY <<'EOF' /usr/local/bin/python-entrypoint.py
#!/usr/bin/env python3
"""
Auto-detects FastAPI/Flask/Django/CLI apps and selects the best server.
"""

import os
import sys
import logging
import multiprocessing
import pathlib
import importlib.util
import subprocess
import re
from typing import List, Optional, Union, Callable

# ------------------- Logging -------------------
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

PROJECT_DIR = pathlib.Path(os.environ.get("PROJECT_DIR", ".")).resolve()
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", 8000))
BIND = f"{HOST}:{PORT}"
DEV_RELOAD = os.environ.get("DEV_RELOAD", "false").lower() == "true"
DEV_SSL = os.environ.get("DEV_SSL", "false").lower() == "true"
HTTPS_CERT = os.environ.get("HTTPS_CERT")
HTTPS_KEY = os.environ.get("HTTPS_KEY")
MAIN_FILE_OVERRIDE = os.environ.get("MAIN_FILE")
AUTO_INSTALL_SERVERS = os.environ.get("AUTO_INSTALL_SERVERS", "false").lower() == "true"

EXCLUDE_DIRS = {'.venv', '.env', '__pycache__', '.mypy_cache', '.pytest_cache', '.git', '.tox', '.eggs', 'build', 'dist'}
COMMON_ENTRYPOINT_NAMES = ["app.py", "main.py", "run.py", "server.py", "manage.py", "cli.py"]

# ------------------- Utilities -------------------
def parse_gunicorn_config(var_name: str) -> Optional[str]:
    config_path = PROJECT_DIR / "gunicorn.conf.py"
    if not config_path.exists(): return None
    pattern = re.compile(
        rf"^[ \t]*{re.escape(var_name)}[ \t]*=[ \t]*(['\"]?)(.+?)\1[ \t]*(\#.*)?$",
        re.MULTILINE | re.IGNORECASE | re.DOTALL
    )
    try:
        content = config_path.read_text(errors="ignore")
        match = pattern.search(content)
        if match:
            return match.group(2).strip()
    except Exception as e:
        logger.warning(f"Failed to parse gunicorn config variable '{var_name}': {e}")
    return None

def get_gunicorn_option(env_var: str, file_var: str, default: any, cast_func: Callable) -> any:
    env_value = os.environ.get(env_var)
    if env_value is not None:
        try: return cast_func(env_value)
        except ValueError: logger.warning(f"Invalid ENV {env_var}='{env_value}', using default.")
    file_value = parse_gunicorn_config(file_var)
    if file_value is not None:
        try: return cast_func(file_value)
        except ValueError: logger.warning(f"Invalid config {file_var}='{file_value}', using default.")
    return default

CPU_CORES = multiprocessing.cpu_count()
WORKERS = get_gunicorn_option("WORKERS", "workers", CPU_CORES * 2 + 1, int)
TIMEOUT = get_gunicorn_option("TIMEOUT", "timeout", 30, int)
PRELOAD = get_gunicorn_option("PRELOAD", "preload_app", "false", lambda x: x.lower() == "true")
WORKER_CLASS = get_gunicorn_option("WORKER_CLASS", "worker_class", "sync", str)
ACCESS_LOG = get_gunicorn_option("ACCESSLOG", "accesslog", "-", str)
ERROR_LOG = get_gunicorn_option("ERRORLOG", "errorlog", "-", str)

def is_installed(pkg: str) -> bool:
    return importlib.util.find_spec(pkg) is not None

def install_package(pkg: str) -> bool:
    if AUTO_INSTALL_SERVERS:
        logger.info(f"Installing missing package '{pkg}'...")
        try: subprocess.check_call([sys.executable, "-m", "pip", "install", pkg]); return True
        except subprocess.CalledProcessError: logger.error(f"Failed to install '{pkg}'"); return False
    return False

def find_python_files(project_dir: pathlib.Path) -> List[pathlib.Path]:
    files = []
    for f in project_dir.rglob("*.py"):
        if not any(part in EXCLUDE_DIRS for part in f.parts[len(project_dir.parts):]):
            files.append(f)
    return files

# ------------------- Entrypoint Detection -------------------
def select_entrypoint(files: List[pathlib.Path]) -> Union[pathlib.Path, str]:
    if MAIN_FILE_OVERRIDE:
        path_override = PROJECT_DIR / MAIN_FILE_OVERRIDE
        if path_override.exists(): return path_override
        logger.warning(f"MAIN_FILE override '{MAIN_FILE_OVERRIDE}' not found. Falling back.")
        
    scores = {}
    for f in files:
        score = 0
        name = f.name
        text = f.read_text(errors="ignore")
        depth = len(f.relative_to(PROJECT_DIR).parts) - 1
        
        score += max(0, 5 - depth)
        if re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]:", text): score += 10
        if any(k in text for k in ["from fastapi", "import fastapi", "from flask", "import flask"]): score += 20
        if any(k in text for k in ["uvicorn.run(", "hypercorn.run(", "daphne.run("]): score += 30
        if any(k in text for k in ["django.core.management", "django-admin"]): score += 30
        if any(k in text for k in ["import argparse", "import click", "import typer"]): score += 15
        
        if name == "app.py": score += 25
        elif name == "main.py": score += 20
        elif name in ("run.py", "server.py"): score += 15
        elif name in ("manage.py", "cli.py"): score += 20
        
        scores[f] = score
    
    if scores and max(scores.values()) > 0: return max(scores, key=scores.get)

    for name in COMMON_ENTRYPOINT_NAMES:
        candidate = PROJECT_DIR / name
        if candidate.exists(): return candidate
    
    pkg_main = list(PROJECT_DIR.rglob("__main__.py"))
    if pkg_main: return f"__MODULE_EXEC__:{pkg_main[0].parent.name}"
    
    raise FileNotFoundError("No suitable Python entrypoint found.")

# ------------------- Framework Detection -------------------
def detect_framework_and_app(file_path: pathlib.Path):
    text = file_path.read_text(errors="ignore")
    if re.search(r"(from|import)\s+fastapi", text):
        m = re.search(r"([a-zA-Z_][a-zA-Z0-9_]*)\s*[:=]\s*FastAPI\(", text)
        return "fastapi", m.group(1) if m else "app"
    if re.search(r"(from|import)\s+flask", text):
        m = re.search(r"([a-zA-Z_][a-zA-Z0-9_]*)\s*[:=]\s*Flask\(", text)
        return "flask", m.group(1) if m else "app"
    if "django.core.management" in text or "django-admin" in text: return "django", None
    if any(k in text for k in ["import argparse", "import click", "import typer"]): return "cli", None
    return None, None

# ------------------- Command Builder -------------------
def build_cmd(framework: str, entrypoint: pathlib.Path, app_var: Optional[str]) -> List[str]:
    module_path = ".".join(entrypoint.relative_to(PROJECT_DIR).with_suffix("").parts)
    app_string = f"{module_path}:{app_var}" if app_var else ""
    ssl_args = []
    if HTTPS_CERT and HTTPS_KEY: ssl_args = ["--ssl-certfile", HTTPS_CERT, "--ssl-keyfile", HTTPS_KEY]
    elif DEV_SSL: logger.warning("DEV_SSL enabled but no certificates provided. Skipping SSL.")
    worker_class_to_use = WORKER_CLASS

    if framework == "cli" or (app_var is None and framework not in ("fastapi", "flask", "django")):
        return [sys.executable, str(entrypoint)]

    if framework == "fastapi" and worker_class_to_use.lower() == "sync":
        worker_class_to_use = "uvicorn.workers.UvicornWorker"

    if framework == "django":
        wsgi_files = list(PROJECT_DIR.rglob("wsgi.py"))
        if not wsgi_files:
            logger.warning("Django project detected but no 'wsgi.py' found. Running entrypoint as script.")
            return [sys.executable, str(entrypoint)]
        wsgi_file = wsgi_files[0]
        wsgi_module = ".".join(wsgi_file.relative_to(PROJECT_DIR).with_suffix("").parts)
        app_string = f"{wsgi_module}:application"
        if worker_class_to_use.lower() in ("uvicorn.workers.uvicornworker", "gunicorn.workers.gthread"):
            worker_class_to_use = "sync"

    server_candidates = ["gunicorn", "uvicorn", "hypercorn"]

    for server in server_candidates:
        if not (is_installed(server) or install_package(server)): continue
        if server == "gunicorn":
            cmd = ["gunicorn", app_string, "-w", str(WORKERS), "-k", worker_class_to_use,
                   "--bind", BIND, "--timeout", str(TIMEOUT),
                   "--access-logfile", ACCESS_LOG, "--error-logfile", ERROR_LOG]
            if PRELOAD: cmd.append("--preload")
            return cmd + [s.replace('--ssl-', '--') for s in ssl_args]
        if framework == "fastapi":
            if server == "uvicorn":
                cmd = ["uvicorn", app_string, "--host", HOST, "--port", str(PORT), "--workers", str(WORKERS)]
                if DEV_RELOAD: cmd.append("--reload")
                return cmd + ssl_args
            elif server == "hypercorn":
                cmd = ["hypercorn", app_string, "--bind", BIND, "--workers", str(WORKERS)]
                return cmd + [s.replace('--ssl-', '--') for s in ssl_args]

    if framework in ("fastapi", "flask", "django"):
        sys.exit(f"FATAL: {framework} detected but no production ASGI/WSGI server is installed.")

    return [sys.executable, str(entrypoint)]

# ------------------- Main -------------------
def main():
    python_files = find_python_files(PROJECT_DIR)
    if not python_files: sys.exit(f"No Python files found in {PROJECT_DIR}")
    try: entrypoint = select_entrypoint(python_files)
    except FileNotFoundError as e: sys.exit(e)
    if isinstance(entrypoint,str) and entrypoint.startswith("__MODULE_EXEC__"):
        pkg_name = entrypoint.split(":")[1]
        cmd = [sys.executable,"-m",pkg_name]; framework="module"
    else:
        framework, app_var = detect_framework_and_app(entrypoint)
        cmd = build_cmd(framework, entrypoint, app_var)
    logger.info(f"Entrypoint selected: {entrypoint}")
    logger.info(f"Framework detected: {framework or 'unknown'}")
    logger.info(f"Starting command: {' '.join(cmd)}")
    os.execvp(cmd[0], cmd)

if __name__ == "__main__": main()
EOF

RUN chmod +x /usr/local/bin/python-entrypoint.py

ENTRYPOINT ["/usr/local/bin/python-entrypoint.py"]

# ========================
# Stage 6: Release image
# ========================
FROM prod AS release
EXPOSE ${PORT:-3000}
LABEL maintainer="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"
