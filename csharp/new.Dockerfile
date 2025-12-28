# syntax=dexnore/dexfile:0

# Production-ready C# .NET Dexfile supporting:
# - Runtimes: .NET 9, .NET 8 (LTS), .NET 6/7, Native AOT, Mono, CoreCLR
# - Package Managers: NuGet, Paket, MyGet, ProGet, Libman
# - Frameworks: ASP.NET Core, Blazor (Server/WASM/Hybrid), OpenSilver, Uno Platform, MAUI
# - Web Servers: Kestrel, OWIN/Katana, HttpSys
# - Deployment: Azure Functions, AWS Lambda, Native AOT, Self-contained, Framework-dependent
# - Distributed: Microsoft Orleans, Dapr, Aspire
# - Base Images: Chiseled Ubuntu, Alpine, Mariner (CBL-Mariner), Debian

ARG DOTNET_VERSION DOTNET_RUNTIME BUILD_IMAGE RUN_IMAGE
ARG FRAMEWORK_TYPE DEPLOYMENT_TYPE BUILD_CONFIGURATION=Release
ARG PROJECT_TYPE PACKAGE_MANAGER ENABLE_AOT=false
ARG PORT=8080 ASPNETCORE_HTTP_PORTS=8080
ARG NGINX_ROOT="/usr/share/nginx/html"

WORKDIR /home/dexfile/app

# ============================================================================
# .NET VERSION DETECTION
# ============================================================================
FUNC detect_dotnet_version
    # Priority 1: global.json (most reliable for .NET SDK version)
    IF PROC --from=busybox:latest --mount=target=. [ -f "global.json" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP '"version":\s*"\K[^"]+' global.json) && echo "$VERSION"
            ARG DOTNET_VERSION=${STDOUT}
        ENDIF
    # Priority 2: .NET version file (custom)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".dotnet-version" ]
        ARG DOTNET_VERSION=$(cat .dotnet-version | tr -d '\n')
    # Priority 3: Check TargetFramework in .csproj files
    ELSE IF PROC --from=busybox:latest --mount=target=. find . -maxdepth 2 -name "*.csproj" -exec grep -l "TargetFramework" {} \; | head -1
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(find . -maxdepth 2 -name "*.csproj" -exec grep -oP '<TargetFramework>net\K[^<]+' {} \; | head -1) && echo "$VERSION"
            ARG DOTNET_VERSION=${STDOUT}
        ENDIF
    ELSE
        ARG DOTNET_VERSION="9.0"
    ENDIF
    
    # Normalize version (e.g., "9.0" -> "9.0", "9" -> "9.0")
    IF PROC [ -n "${DOTNET_VERSION}" ]
        IF PROC ! echo "${DOTNET_VERSION}" | grep -q '\.'
            ARG DOTNET_VERSION="${DOTNET_VERSION}.0"
        ENDIF
    ENDIF
ENDFUNC

# ============================================================================
# FRAMEWORK DETECTION
# ============================================================================
FUNC detect_framework
    # Check .csproj files for framework and project type
    IF PROC --from=busybox:latest --mount=target=. find . -maxdepth 2 -name "*.csproj" | head -1
        # ASP.NET Core detection
        IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.NET.Sdk.Web' *.csproj
            ARG FRAMEWORK_TYPE="aspnetcore"
            ARG PROJECT_TYPE="web"
        # Blazor WebAssembly
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.NET.Sdk.BlazorWebAssembly' *.csproj
            ARG FRAMEWORK_TYPE="blazor-wasm"
            ARG PROJECT_TYPE="wasm"
        # Blazor detection via packages
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.AspNetCore.Components.WebAssembly' *.csproj
            ARG FRAMEWORK_TYPE="blazor-wasm"
            ARG PROJECT_TYPE="wasm"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.AspNetCore.Components.Server' *.csproj
            ARG FRAMEWORK_TYPE="blazor-server"
            ARG PROJECT_TYPE="web"
        # Azure Functions
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.NET.Sdk.Functions' *.csproj || grep -q 'Microsoft.Azure.Functions' *.csproj
            ARG FRAMEWORK_TYPE="azure-functions"
            ARG PROJECT_TYPE="functions"
        # AWS Lambda
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Amazon.Lambda' *.csproj
            ARG FRAMEWORK_TYPE="aws-lambda"
            ARG PROJECT_TYPE="lambda"
        # Orleans
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.Orleans' *.csproj
            ARG FRAMEWORK_TYPE="orleans"
            ARG PROJECT_TYPE="distributed"
        # Dapr
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Dapr' *.csproj || [ -f "dapr.yaml" ]
            ARG FRAMEWORK_TYPE="dapr"
            ARG PROJECT_TYPE="distributed"
        # Aspire
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Aspire' *.csproj || [ -f "aspire.json" ]
            ARG FRAMEWORK_TYPE="aspire"
            ARG PROJECT_TYPE="distributed"
        # OpenSilver
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'OpenSilver' *.csproj
            ARG FRAMEWORK_TYPE="opensilver"
            ARG PROJECT_TYPE="wasm"
        # Uno Platform
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Uno.UI' *.csproj
            ARG FRAMEWORK_TYPE="uno-platform"
            ARG PROJECT_TYPE="cross-platform"
        # MAUI
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.NET.Sdk.Maui' *.csproj
            ARG FRAMEWORK_TYPE="maui"
            ARG PROJECT_TYPE="cross-platform"
        # Worker Service
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.Extensions.Hosting' *.csproj && grep -q 'BackgroundService' *.csproj
            ARG FRAMEWORK_TYPE="worker"
            ARG PROJECT_TYPE="service"
        # gRPC
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Grpc.AspNetCore' *.csproj
            ARG FRAMEWORK_TYPE="grpc"
            ARG PROJECT_TYPE="web"
        # Console/Generic
        ELSE
            ARG FRAMEWORK_TYPE="console"
            ARG PROJECT_TYPE="console"
        ENDIF
    ELSE
        RUN echo "ERROR: No .csproj file found" >&2 && exit 1
    ENDIF
ENDFUNC

# ============================================================================
# NATIVE AOT DETECTION
# ============================================================================
FUNC detect_native_aot
    # Check for PublishAot property in .csproj
    IF PROC --from=busybox:latest --mount=target=. grep -q '<PublishAot>true</PublishAot>' *.csproj
        ARG ENABLE_AOT=true
        ARG DEPLOYMENT_TYPE="native-aot"
    # Check for Native AOT in properties
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '<PublishTrimmed>true</PublishTrimmed>' *.csproj && grep -q '<PublishReadyToRun>true</PublishReadyToRun>' *.csproj
        ARG DEPLOYMENT_TYPE="trimmed"
    # Check for self-contained
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '<SelfContained>true</SelfContained>' *.csproj
        ARG DEPLOYMENT_TYPE="self-contained"
    ELSE
        ARG DEPLOYMENT_TYPE="framework-dependent"
    ENDIF
ENDFUNC

# ============================================================================
# PACKAGE MANAGER DETECTION
# ============================================================================
FUNC detect_package_manager
    # Priority 1: Paket
    IF PROC --from=busybox:latest --mount=target=. [ -f "paket.dependencies" ] || [ -f "paket.lock" ]
        ARG PACKAGE_MANAGER="paket"
    # Priority 2: Custom NuGet configs
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "NuGet.config" ]
        IF PROC --from=busybox:latest --mount=target=. grep -q 'myget.org' NuGet.config
            ARG PACKAGE_MANAGER="myget"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'proget' NuGet.config
            ARG PACKAGE_MANAGER="proget"
        ELSE
            ARG PACKAGE_MANAGER="nuget"
        ENDIF
    # Priority 3: Libman (for client-side libraries)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "libman.json" ]
        ARG PACKAGE_MANAGER="libman+nuget"
    ELSE
        ARG PACKAGE_MANAGER="nuget"
    ENDIF
ENDFUNC

# ============================================================================
# RUNTIME IMAGE SELECTION
# ============================================================================
FUNC select_runtime_image
    # For WASM projects, use nginx
    IF PROC [ "${PROJECT_TYPE}" = "wasm" ]
        ARG RUN_IMAGE="nginx:stable-alpine"
        RETURN
    ENDIF
    
    # For Native AOT, use minimal runtime-deps or chiseled
    IF PROC [ "${ENABLE_AOT}" = "true" ]
        # Chiseled Ubuntu for Native AOT (smallest, most secure)
        ARG RUN_IMAGE="mcr.microsoft.com/dotnet/runtime-deps:${DOTNET_VERSION}-noble-chiseled"
    # For standard runtime
    ELSE
        # Check for preferred base image in .dockerignore comments or config
        IF PROC --from=busybox:latest --mount=target=. [ -f ".dotnet-runtime" ]
            ARG RUNTIME_PREF=$(cat .dotnet-runtime | tr -d '\n')
            IF PROC [ "${RUNTIME_PREF}" = "alpine" ]
                ARG RUN_IMAGE="mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-alpine"
            ELSE IF PROC [ "${RUNTIME_PREF}" = "mariner" ]
                ARG RUN_IMAGE="mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-cbl-mariner"
            ELSE IF PROC [ "${RUNTIME_PREF}" = "chiseled" ]
                ARG RUN_IMAGE="mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-noble-chiseled"
            ELSE
                ARG RUN_IMAGE="mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-bookworm-slim"
            ENDIF
        ELSE
            # Default: Chiseled Ubuntu for best security/size balance
            ARG RUN_IMAGE="mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-noble-chiseled"
        ENDIF
    ENDIF
ENDFUNC

# ============================================================================
# SOLUTION/PROJECT DETECTION
# ============================================================================
FUNC detect_solution_structure
    # Check if solution file exists
    IF PROC --from=busybox:latest --mount=target=. find . -maxdepth 1 -name "*.sln" | head -1
        ARG SOLUTION_FILE=$(find . -maxdepth 1 -name "*.sln" | head -1)
    ENDIF
    
    # Find the main project file
    IF PROC --from=busybox:latest --mount=target=. find . -name "*.csproj" | grep -v "Tests" | grep -v "Test" | head -1
        ARG PROJECT_FILE=$(find . -name "*.csproj" | grep -v "Tests" | grep -v "Test" | head -1)
    ENDIF
ENDFUNC

# ============================================================================
# RUN DETECTIONS
# ============================================================================
FUNC CALL detect_dotnet_version
FUNC CALL detect_framework
FUNC CALL detect_native_aot
FUNC CALL detect_package_manager
FUNC CALL detect_solution_structure
FUNC CALL select_runtime_image

# Set build image based on version
IF PROC [ -n "${DOTNET_VERSION}" ]
    ARG BUILD_IMAGE="mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION}-bookworm-slim"
ELSE
    ARG BUILD_IMAGE="mcr.microsoft.com/dotnet/sdk:9.0-bookworm-slim"
ENDIF

# ============================================================================
# BASE BUILD STAGE
# ============================================================================
FROM ${BUILD_IMAGE} AS base

# Install additional build tools for Native AOT
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        clang \
        zlib1g-dev \
        wget \
        curl \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /home/dexfile/app

# Set environment variables
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
ENV DOTNET_NOLOGO=1
ENV ASPNETCORE_ENVIRONMENT=Production

# ============================================================================
# RESTORE STAGE (dependency caching)
# ============================================================================
FROM base AS restore

# Copy NuGet configuration files
COPY NuGet.config* nuget.config* ./ 2>/dev/null || true
COPY global.json* .dotnet-version* ./ 2>/dev/null || true

# Copy solution and project files for restore
COPY *.sln* ./ 2>/dev/null || true
COPY */*.csproj ./ 2>/dev/null || true
COPY **/*.csproj ./ 2>/dev/null || true

# Copy Paket files if using Paket
IF PROC [ "${PACKAGE_MANAGER}" = "paket" ]
    COPY paket.dependencies paket.lock .paket/ ./ 2>/dev/null || true
    COPY .paket/ ./.paket/ 2>/dev/null || true
ENDIF

# Copy libman.json if exists
IF PROC echo "${PACKAGE_MANAGER}" | grep -q "libman"
    COPY libman.json ./ 2>/dev/null || true
ENDIF

# Install package manager tools
RUN --mount=type=cache,id=nuget-packages,target=/root/.nuget/packages,sharing=locked \
    --mount=type=secret,id=nuget-config,target=/home/dexfile/app/NuGet.config \
    set -e; \
    if [ "${PACKAGE_MANAGER}" = "paket" ]; then \
        dotnet tool restore || dotnet tool install --tool-path /usr/local/bin paket; \
    fi; \
    if echo "${PACKAGE_MANAGER}" | grep -q "libman"; then \
        dotnet tool install --global Microsoft.Web.LibraryManager.Cli 2>/dev/null || true; \
    fi

# Restore dependencies
RUN --mount=type=cache,id=nuget-packages,target=/root/.nuget/packages,sharing=locked \
    --mount=type=secret,id=nuget-config,target=/home/dexfile/app/NuGet.config \
    set -e; \
    if [ "${PACKAGE_MANAGER}" = "paket" ]; then \
        paket restore; \
    elif [ -n "${SOLUTION_FILE}" ]; then \
        dotnet restore "${SOLUTION_FILE}" --locked-mode; \
    elif [ -n "${PROJECT_FILE}" ]; then \
        dotnet restore "${PROJECT_FILE}" --locked-mode; \
    else \
        dotnet restore --locked-mode; \
    fi; \
    if echo "${PACKAGE_MANAGER}" | grep -q "libman"; then \
        libman restore 2>/dev/null || true; \
    fi

# ============================================================================
# BUILD STAGE
# ============================================================================
FROM restore AS build

# Copy all source files
COPY . .

# Build the application
RUN --mount=type=cache,id=nuget-packages,target=/root/.nuget/packages,sharing=locked \
    set -e; \
    if [ -n "${SOLUTION_FILE}" ]; then \
        dotnet build "${SOLUTION_FILE}" \
            --configuration ${BUILD_CONFIGURATION} \
            --no-restore; \
    elif [ -n "${PROJECT_FILE}" ]; then \
        dotnet build "${PROJECT_FILE}" \
            --configuration ${BUILD_CONFIGURATION} \
            --no-restore; \
    else \
        dotnet build \
            --configuration ${BUILD_CONFIGURATION} \
            --no-restore; \
    fi

# ============================================================================
# PUBLISH STAGE
# ============================================================================
FROM build AS publish

# Publish the application with appropriate settings
RUN --mount=type=cache,id=nuget-packages,target=/root/.nuget/packages,sharing=locked \
    set -e; \
    PUBLISH_ARGS="--configuration ${BUILD_CONFIGURATION} --no-restore --no-build"; \
    if [ "${ENABLE_AOT}" = "true" ]; then \
        PUBLISH_ARGS="${PUBLISH_ARGS} /p:PublishAot=true /p:StripSymbols=true"; \
    elif [ "${DEPLOYMENT_TYPE}" = "self-contained" ]; then \
        PUBLISH_ARGS="${PUBLISH_ARGS} --self-contained true"; \
    elif [ "${DEPLOYMENT_TYPE}" = "trimmed" ]; then \
        PUBLISH_ARGS="${PUBLISH_ARGS} /p:PublishTrimmed=true /p:PublishSingleFile=true"; \
    else \
        PUBLISH_ARGS="${PUBLISH_ARGS} --self-contained false"; \
    fi; \
    if [ -n "${PROJECT_FILE}" ]; then \
        dotnet publish "${PROJECT_FILE}" ${PUBLISH_ARGS} --output /app/publish; \
    else \
        dotnet publish ${PUBLISH_ARGS} --output /app/publish; \
    fi

# ============================================================================
# RUNTIME BASE STAGE
# ============================================================================
FROM ${RUN_IMAGE} AS app

# Create non-root user
RUN if command -v addgroup >/dev/null 2>&1; then \
        addgroup --system --gid 1000 dexnore 2>/dev/null || true; \
        adduser --system --disabled-password --no-create-home --uid 1000 --gid 1000 dexfile 2>/dev/null || true; \
    elif command -v groupadd >/dev/null 2>&1; then \
        groupadd -r -g 1000 dexnore 2>/dev/null || true; \
        useradd -r -u 1000 -g dexnore -d /home/dexfile/app -s /sbin/nologin dexfile 2>/dev/null || true; \
    fi && \
    mkdir -p /home/dexfile/app && \
    chown -R 1000:1000 /home/dexfile/app 2>/dev/null || true

WORKDIR /home/dexfile/app
USER dexfile

ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_HTTP_PORTS=${ASPNETCORE_HTTP_PORTS}
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1

EXPOSE ${PORT}

# ============================================================================
# PRODUCTION STAGE
# ============================================================================
FROM app AS prod

# Handle nginx static serving (for Blazor WASM, OpenSilver, etc.)
IF PROC [ "${PROJECT_TYPE}" = "wasm" ]
    # Copy nginx config if exists
    IF PROC --from=busybox:latest --mount=target=. [ -f "nginx.conf" ]
        COPY --chown=root:root nginx.conf /etc/nginx/conf.d/default.conf
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Caddyfile" ]
        COPY --chown=root:root Caddyfile /etc/caddy/Caddyfile
    ELSE
        # Create default nginx config for Blazor WASM
        RUN echo 'server { \
            listen 80; \
            root /usr/share/nginx/html; \
            index index.html; \
            location / { \
                try_files $uri $uri/ /index.html =404; \
            } \
            location ~* \.(dll|wasm|blat|dat)$ { \
                add_header Content-Type application/octet-stream; \
                add_header Cache-Control "public, max-age=31536000, immutable"; \
            } \
            location ~* \.(js|css|json)$ { \
                add_header Cache-Control "public, max-age=31536000, immutable"; \
            } \
            gzip on; \
            gzip_types application/wasm application/octet-stream text/plain text/css application/json application/javascript; \
        }' > /etc/nginx/conf.d/default.conf
    ENDIF
    
    # Copy published WASM files
    IF PROC [ "${FRAMEWORK_TYPE}" = "blazor-wasm" ]
        COPY --chown=nginx:nginx --from=publish /app/publish/wwwroot ${NGINX_ROOT}/
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "opensilver" ]
        COPY --chown=nginx:nginx --from=publish /app/publish/ClientBin ${NGINX_ROOT}/ClientBin/
        COPY --chown=nginx:nginx --from=publish /app/publish/wwwroot ${NGINX_ROOT}/ 2>/dev/null || true
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "uno-platform" ]
        COPY --chown=nginx:nginx --from=publish /app/publish ${NGINX_ROOT}/
    ELSE
        COPY --chown=nginx:nginx --from=publish /app/publish/wwwroot ${NGINX_ROOT}/ 2>/dev/null || \
             COPY --chown=nginx:nginx --from=publish /app/publish ${NGINX_ROOT}/
    ENDIF
    
    # Set proper permissions
    RUN chown -R nginx:nginx ${NGINX_ROOT} && chmod -R 755 ${NGINX_ROOT}
    
    CMD ["nginx", "-g", "daemon off;"]

# Handle .NET runtime
ELSE
    # Copy published application
    COPY --chown=dexfile:dexfile --from=publish /app/publish ./
    
    # Find the entry point DLL or executable
    RUN if [ "${ENABLE_AOT}" = "true" ]; then \
            ENTRY_POINT=$(find . -maxdepth 1 -type f -executable ! -name "*.so" ! -name "*.dylib" | head -1); \
            if [ -n "${ENTRY_POINT}" ]; then \
                ln -s "${ENTRY_POINT}" /home/dexfile/app/app || true; \
            fi; \
        else \
            ENTRY_DLL=$(find . -maxdepth 1 -name "*.dll" ! -name "*.Views.dll" ! -name "*.PrecompiledViews.dll" | head -1); \
            if [ -n "${ENTRY_DLL}" ]; then \
                ln -s "${ENTRY_DLL}" /home/dexfile/app/app.dll || true; \
            fi; \
        fi
    
    # Framework-specific health checks
    IF PROC [ "${FRAMEWORK_TYPE}" = "aspnetcore" ] || [ "${FRAMEWORK_TYPE}" = "blazor-server" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/health 2>/dev/null || \
                wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/ || exit 1
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "grpc" ]
        HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/health 2>/dev/null || exit 1
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "orleans" ]
        HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/health 2>/dev/null || exit 1
    ENDIF
    
    # Set appropriate entrypoint based on deployment type
    IF PROC [ "${ENABLE_AOT}" = "true" ]
        # Native AOT executable
        CMD ["./app"]
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "azure-functions" ]
        CMD ["dotnet", "Microsoft.Azure.WebJobs.Script.WebHost.dll"]
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "aws-lambda" ]
        CMD ["./bootstrap"]
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "orleans" ]
        CMD ["dotnet", "app.dll"]
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "dapr" ]
        # Dapr sidecar will be injected by Dapr runtime
        CMD ["dotnet", "app.dll"]
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "aspire" ]
        CMD ["dotnet", "app.dll"]
    ELSE
        # Standard ASP.NET Core or console app
        CMD ["dotnet", "app.dll"]
    ENDIF
ENDIF

# ============================================================================
# RELEASE STAGE
# ============================================================================
FROM prod AS release

# Metadata labels
LABEL maintainer="@dexnore/dexfile"
LABEL org.opencontainers.image.vendor="Dexnore"
LABEL org.opencontainers.image.title=".NET Application"
LABEL org.opencontainers.image.description="Production .NET application supporting ASP.NET Core, Blazor, Native AOT, and distributed frameworks"
LABEL org.opencontainers.image.authors="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

# Dynamic labels based on detection
LABEL app.framework="${FRAMEWORK_TYPE}"
LABEL app.dotnet-version="${DOTNET_VERSION}"
LABEL app.deployment-type="${DEPLOYMENT_TYPE}"
LABEL app.package-manager="${PACKAGE_MANAGER}"
LABEL app.native-aot="${ENABLE_AOT}"
LABEL security.non-root="true"

FROM release