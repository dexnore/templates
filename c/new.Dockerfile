# syntax=dexnore/dexfile:0

# Production-ready C/C++ Dexfile supporting:
# - Build Systems: CMake, Ninja, Meson, Make, Bazel, xmake, Premake, SCons, Autotools
# - Package Managers: Conan, vcpkg, Hunter, CPM, Buckaroo, build2
# - Compilers: GCC, Clang, Intel ICC, TinyCC, musl-gcc
# - Standards: C89/C99/C11/C17/C23, C++98/11/14/17/20/23
# - Static Analysis: Clang-Tidy, Cppcheck, Infer, scan-build
# - Optimization: ccache, distcc, sccache, icecc
# - Build Tools: Bear (compilation database), compile_commands.json
# - Frameworks: libuv, libev, libevent, Boost, Qt, GTK, SDL2, SFML, GLFW
# - Web: libmicrohttpd, facil.io, H2O, Mongoose, Crow (C++), Drogon, oatpp
# - Embedded: Zephyr RTOS, FreeRTOS, Arduino, PlatformIO

ARG BUILD_IMAGE="gcc:bookworm" RUN_IMAGE="debian:bookworm-slim"
ARG COMPILER=gcc COMPILER_VERSION BUILD_SYSTEM CMAKE_VERSION=3.27
ARG C_STANDARD CXX_STANDARD BUILD_TYPE=Release
ARG PACKAGE_MANAGER ANALYSIS_TOOL CACHE_TOOL
ARG ENABLE_LTO=false ENABLE_STATIC=true ENABLE_SANITIZERS=false
ARG CROSS_COMPILE TARGET_ARCH TOOLCHAIN_FILE
ARG PORT=8080

WORKDIR /home/dexfile/app

# ============================================================================
# COMPILER DETECTION
# ============================================================================
FUNC detect_compiler
    # Priority 1: .compiler file
    IF PROC --from=busybox:latest --mount=target=. [ -f ".compiler" ]
        ARG COMPILER=$(cat .compiler | tr -d '\n')
    # Priority 2: CC environment in scripts
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "build.sh" ] && grep -q "CC=" build.sh
        IF PROC --from=busybox:latest --mount=target=. COMP=$(grep -oP 'CC=\K[^\s]+' build.sh | head -1) && echo "$COMP"
            ARG COMPILER=${STDOUT}
        ENDIF
    # Priority 3: CMakeLists.txt compiler hints
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "CMakeLists.txt" ]
        IF PROC --from=busybox:latest --mount=target=. grep -q "CMAKE_C_COMPILER.*clang" CMakeLists.txt
            ARG COMPILER="clang"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "CMAKE_CXX_COMPILER.*clang" CMakeLists.txt
            ARG COMPILER="clang"
        ENDIF
    # Priority 4: Check for .clang files
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".clang-format" ] || [ -f ".clang-tidy" ]
        ARG COMPILER="clang"
    ELSE
        ARG COMPILER="gcc"
    ENDIF
    
    # Detect compiler version
    IF PROC --from=busybox:latest --mount=target=. [ -f ".compiler-version" ]
        ARG COMPILER_VERSION=$(cat .compiler-version | tr -d '\n')
    ENDIF
ENDFUNC

# ============================================================================
# BUILD SYSTEM DETECTION
# ============================================================================
FUNC detect_build_system
    # Priority order: most specific to most generic
    IF PROC --from=busybox:latest --mount=target=. [ -f "BUILD" ] || [ -f "WORKSPACE" ] || [ -f "BUILD.bazel" ]
        ARG BUILD_SYSTEM="bazel"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "meson.build" ]
        ARG BUILD_SYSTEM="meson"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "CMakeLists.txt" ]
        ARG BUILD_SYSTEM="cmake"
        # Detect if CMake uses Ninja
        IF PROC --from=busybox:latest --mount=target=. grep -q "Ninja" CMakeLists.txt || [ -f "build.ninja" ]
            ARG BUILD_SYSTEM="cmake-ninja"
        ENDIF
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "xmake.lua" ]
        ARG BUILD_SYSTEM="xmake"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "premake5.lua" ] || [ -f "premake4.lua" ]
        ARG BUILD_SYSTEM="premake"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "SConstruct" ] || [ -f "SConscript" ]
        ARG BUILD_SYSTEM="scons"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "configure.ac" ] || [ -f "configure.in" ]
        ARG BUILD_SYSTEM="autotools"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Makefile" ] || [ -f "makefile" ] || [ -f "GNUmakefile" ]
        ARG BUILD_SYSTEM="make"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "build.ninja" ]
        ARG BUILD_SYSTEM="ninja"
    ELSE
        # Try to detect from common patterns
        IF PROC --from=busybox:latest --mount=target=. find . -name "*.cmake" | head -1
            ARG BUILD_SYSTEM="cmake"
        ELSE IF PROC --from=busybox:latest --mount=target=. find . -name "Makefile.am" | head -1
            ARG BUILD_SYSTEM="autotools"
        ELSE
            ARG BUILD_SYSTEM="make"
        ENDIF
    ENDIF
ENDFUNC

# ============================================================================
# PACKAGE MANAGER DETECTION
# ============================================================================
FUNC detect_package_manager
    # Priority 1: Conan (trending)
    IF PROC --from=busybox:latest --mount=target=. [ -f "conanfile.txt" ] || [ -f "conanfile.py" ]
        ARG PACKAGE_MANAGER="conan"
    # Priority 2: vcpkg (popular)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "vcpkg.json" ] || [ -f "vcpkg-configuration.json" ]
        ARG PACKAGE_MANAGER="vcpkg"
    # Priority 3: CPM.cmake
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "CPMAddPackage\|CPM.cmake" CMakeLists.txt 2>/dev/null
        ARG PACKAGE_MANAGER="cpm"
    # Priority 4: Hunter
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "HunterGate" CMakeLists.txt 2>/dev/null || [ -f "cmake/Hunter/config.cmake" ]
        ARG PACKAGE_MANAGER="hunter"
    # Priority 5: Buckaroo
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "buckaroo.json" ] || [ -f ".buckconfig" ]
        ARG PACKAGE_MANAGER="buckaroo"
    # Priority 6: build2
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "manifest" ] || [ -f "repositories.manifest" ]
        ARG PACKAGE_MANAGER="build2"
    # Priority 7: System package manager
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "dependencies.txt" ] || [ -f ".apt-packages" ]
        ARG PACKAGE_MANAGER="apt"
    ELSE
        ARG PACKAGE_MANAGER="none"
    ENDIF
ENDFUNC

# ============================================================================
# C/C++ STANDARD DETECTION
# ============================================================================
FUNC detect_standards
    # Detect C standard
    IF PROC --from=busybox:latest --mount=target=. [ -f "CMakeLists.txt" ]
        IF PROC --from=busybox:latest --mount=target=. grep -q "CMAKE_C_STANDARD" CMakeLists.txt
            IF PROC --from=busybox:latest --mount=target=. STD=$(grep -oP 'CMAKE_C_STANDARD\s+\K\d+' CMakeLists.txt | head -1) && echo "$STD"
                ARG C_STANDARD=${STDOUT}
            ENDIF
        ENDIF
        IF PROC --from=busybox:latest --mount=target=. grep -q "CMAKE_CXX_STANDARD" CMakeLists.txt
            IF PROC --from=busybox:latest --mount=target=. STD=$(grep -oP 'CMAKE_CXX_STANDARD\s+\K\d+' CMakeLists.txt | head -1) && echo "$STD"
                ARG CXX_STANDARD=${STDOUT}
            ENDIF
        ENDIF
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "Makefile" ]
        IF PROC --from=busybox:latest --mount=target=. grep -q "\-std=c[0-9]" Makefile
            IF PROC --from=busybox:latest --mount=target=. STD=$(grep -oP '\-std=c\K[0-9]+' Makefile | head -1) && echo "$STD"
                ARG C_STANDARD=${STDOUT}
            ENDIF
        ENDIF
        IF PROC --from=busybox:latest --mount=target=. grep -q "\-std=c\+\+[0-9]" Makefile
            IF PROC --from=busybox:latest --mount=target=. STD=$(grep -oP '\-std=c\+\+\K[0-9]+' Makefile | head -1) && echo "$STD"
                ARG CXX_STANDARD=${STDOUT}
            ENDIF
        ENDIF
    ENDIF
    
    # Set defaults if not detected
    IF PROC [ -z "${C_STANDARD}" ]
        ARG C_STANDARD="11"
    ENDIF
    IF PROC [ -z "${CXX_STANDARD}" ]
        ARG CXX_STANDARD="17"
    ENDIF
ENDFUNC

# ============================================================================
# ANALYSIS TOOL DETECTION
# ============================================================================
FUNC detect_analysis_tools
    IF PROC --from=busybox:latest --mount=target=. [ -f ".clang-tidy" ]
        ARG ANALYSIS_TOOL="clang-tidy"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "cppcheck.xml" ] || [ -f ".cppcheck" ]
        ARG ANALYSIS_TOOL="cppcheck"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".infer-config" ]
        ARG ANALYSIS_TOOL="infer"
    ELSE
        ARG ANALYSIS_TOOL="none"
    ENDIF
ENDFUNC

# ============================================================================
# CACHE TOOL DETECTION
# ============================================================================
FUNC detect_cache_tool
    IF PROC --from=busybox:latest --mount=target=. [ -f ".ccache" ] || [ -f "ccache.conf" ]
        ARG CACHE_TOOL="ccache"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".distcc" ]
        ARG CACHE_TOOL="distcc"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".sccache" ]
        ARG CACHE_TOOL="sccache"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "ccache" CMakeLists.txt 2>/dev/null || grep -q "ccache" Makefile 2>/dev/null
        ARG CACHE_TOOL="ccache"
    ELSE
        ARG CACHE_TOOL="ccache"  # Default to ccache for performance
    ENDIF
ENDFUNC

# ============================================================================
# BUILD OPTIONS DETECTION
# ============================================================================
FUNC detect_build_options
    # Detect LTO (Link Time Optimization)
    IF PROC --from=busybox:latest --mount=target=. grep -q "INTERPROCEDURAL_OPTIMIZATION\|LTO" CMakeLists.txt 2>/dev/null
        ARG ENABLE_LTO=true
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "\-flto" Makefile 2>/dev/null
        ARG ENABLE_LTO=true
    ENDIF
    
    # Detect static linking preference
    IF PROC --from=busybox:latest --mount=target=. grep -q "BUILD_SHARED_LIBS OFF\|static" CMakeLists.txt 2>/dev/null
        ARG ENABLE_STATIC=true
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "\-static" Makefile 2>/dev/null
        ARG ENABLE_STATIC=true
    ENDIF
    
    # Detect sanitizers (for development builds)
    IF PROC --from=busybox:latest --mount=target=. grep -q "sanitize" CMakeLists.txt 2>/dev/null || grep -q "sanitize" Makefile 2>/dev/null
        ARG ENABLE_SANITIZERS=true
    ENDIF
    
    # Detect build type
    IF PROC --from=busybox:latest --mount=target=. grep -q "CMAKE_BUILD_TYPE.*Debug" CMakeLists.txt 2>/dev/null
        ARG BUILD_TYPE="Debug"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "CMAKE_BUILD_TYPE.*RelWithDebInfo" CMakeLists.txt 2>/dev/null
        ARG BUILD_TYPE="RelWithDebInfo"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "CMAKE_BUILD_TYPE.*MinSizeRel" CMakeLists.txt 2>/dev/null
        ARG BUILD_TYPE="MinSizeRel"
    ELSE
        ARG BUILD_TYPE="Release"
    ENDIF
ENDFUNC

# ============================================================================
# CROSS-COMPILATION DETECTION
# ============================================================================
FUNC detect_cross_compile
    # Check for toolchain files
    IF PROC --from=busybox:latest --mount=target=. find . -name "*toolchain.cmake" -o -name "toolchain-*.cmake" | head -1
        IF PROC --from=busybox:latest --mount=target=. FILE=$(find . -name "*toolchain.cmake" -o -name "toolchain-*.cmake" | head -1) && echo "$FILE"
            ARG TOOLCHAIN_FILE=${STDOUT}
            ARG CROSS_COMPILE=true
        ENDIF
    ENDIF
    
    # Check for target architecture specification
    IF PROC --from=busybox:latest --mount=target=. grep -q "CMAKE_SYSTEM_PROCESSOR\|CMAKE_SYSTEM_NAME" CMakeLists.txt 2>/dev/null
        IF PROC --from=busybox:latest --mount=target=. ARCH=$(grep -oP 'CMAKE_SYSTEM_PROCESSOR\s+\K[^\)]+' CMakeLists.txt | head -1) && echo "$ARCH"
            ARG TARGET_ARCH=${STDOUT}
        ENDIF
    ENDIF
    
    # Check for embedded targets
    IF PROC --from=busybox:latest --mount=target=. [ -f "platformio.ini" ]
        ARG CROSS_COMPILE=true
        ARG BUILD_SYSTEM="platformio"
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "zephyr/CMakeLists.txt" ] || grep -q "Zephyr-Kernel" CMakeLists.txt 2>/dev/null
        ARG CROSS_COMPILE=true
        ARG BUILD_SYSTEM="zephyr"
    ENDIF
ENDFUNC

# ============================================================================
# FRAMEWORK DETECTION
# ============================================================================
FUNC detect_framework
    # Web frameworks
    IF PROC --from=busybox:latest --mount=target=. grep -q "microhttpd\|MHD_" *.c *.cpp *.h *.hpp 2>/dev/null
        ARG FRAMEWORK_TYPE="libmicrohttpd"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "facil\.io\|FIO_" *.c *.h 2>/dev/null
        ARG FRAMEWORK_TYPE="facil.io"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "h2o\.h\|H2O_" *.c *.h 2>/dev/null
        ARG FRAMEWORK_TYPE="h2o"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "mongoose\.h\|MG_" *.c *.h 2>/dev/null
        ARG FRAMEWORK_TYPE="mongoose"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "crow\.h\|Crow\|CROW_" *.cpp *.hpp 2>/dev/null
        ARG FRAMEWORK_TYPE="crow"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "drogon/\|Drogon" *.cpp *.hpp 2>/dev/null
        ARG FRAMEWORK_TYPE="drogon"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "oatpp/\|OATPP_" *.cpp *.hpp 2>/dev/null
        ARG FRAMEWORK_TYPE="oatpp"
    # Async I/O frameworks
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "uv\.h\|uv_" *.c *.h 2>/dev/null || grep -q "libuv" CMakeLists.txt 2>/dev/null
        ARG FRAMEWORK_TYPE="libuv"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "ev\.h\|ev_" *.c *.h 2>/dev/null || grep -q "libev" CMakeLists.txt 2>/dev/null
        ARG FRAMEWORK_TYPE="libev"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "event\.h\|event_" *.c *.h 2>/dev/null || grep -q "libevent" CMakeLists.txt 2>/dev/null
        ARG FRAMEWORK_TYPE="libevent"
    # UI frameworks
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "boost/" *.cpp *.hpp 2>/dev/null || grep -q "Boost" CMakeLists.txt 2>/dev/null
        ARG FRAMEWORK_TYPE="boost"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "Qt\|qmake" *.cpp *.hpp CMakeLists.txt 2>/dev/null || [ -f "*.pro" ]
        ARG FRAMEWORK_TYPE="qt"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "gtk/\|GTK_" *.c *.h 2>/dev/null
        ARG FRAMEWORK_TYPE="gtk"
    # Game/Graphics frameworks
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "SDL\.h\|SDL_" *.c *.cpp *.h 2>/dev/null
        ARG FRAMEWORK_TYPE="sdl2"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "SFML/\|sf::" *.cpp *.hpp 2>/dev/null
        ARG FRAMEWORK_TYPE="sfml"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "GLFW/\|glfw" *.c *.cpp *.h 2>/dev/null
        ARG FRAMEWORK_TYPE="glfw"
    ELSE
        ARG FRAMEWORK_TYPE="generic"
    ENDIF
ENDFUNC

# ============================================================================
# RUN DETECTIONS
# ============================================================================
FUNC CALL detect_compiler
FUNC CALL detect_build_system
FUNC CALL detect_package_manager
FUNC CALL detect_standards
FUNC CALL detect_analysis_tools
FUNC CALL detect_cache_tool
FUNC CALL detect_build_options
FUNC CALL detect_cross_compile
FUNC CALL detect_framework

# Set build image based on compiler
IF PROC [ "${COMPILER}" = "clang" ]
    IF PROC [ -n "${COMPILER_VERSION}" ]
        ARG BUILD_IMAGE="silkeh/clang:${COMPILER_VERSION}"
    ELSE
        ARG BUILD_IMAGE="silkeh/clang:latest"
    ENDIF
ELSE IF PROC [ "${COMPILER}" = "gcc" ]
    IF PROC [ -n "${COMPILER_VERSION}" ]
        ARG BUILD_IMAGE="gcc:${COMPILER_VERSION}-bookworm"
    ELSE
        ARG BUILD_IMAGE="gcc:bookworm"
    ENDIF
ELSE IF PROC [ "${COMPILER}" = "musl-gcc" ]
    ARG BUILD_IMAGE="alpine:latest"
ELSE
    ARG BUILD_IMAGE="gcc:bookworm"
ENDIF

# ============================================================================
# BASE BUILD STAGE
# ============================================================================
FROM ${BUILD_IMAGE} AS base

# Install build essentials
RUN if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            build-essential \
            cmake \
            ninja-build \
            make \
            pkg-config \
            git \
            curl \
            wget \
            ca-certificates \
            python3 \
            python3-pip \
            autoconf \
            automake \
            libtool \
            file \
            patch; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache \
            build-base \
            cmake \
            ninja \
            make \
            pkgconfig \
            git \
            curl \
            wget \
            ca-certificates \
            python3 \
            py3-pip \
            autoconf \
            automake \
            libtool \
            file \
            patch \
            musl-dev \
            linux-headers; \
    fi

# Install compiler if not in base image
RUN if [ "${COMPILER}" = "clang" ] && ! command -v clang >/dev/null 2>&1; then \
        if command -v apt-get >/dev/null 2>&1; then \
            apt-get install -y clang lldb lld; \
        elif command -v apk >/dev/null 2>&1; then \
            apk add --no-cache clang llvm lld; \
        fi; \
    elif [ "${COMPILER}" = "gcc" ] && ! command -v gcc >/dev/null 2>&1; then \
        if command -v apt-get >/dev/null 2>&1; then \
            apt-get install -y gcc g++; \
        elif command -v apk >/dev/null 2>&1; then \
            apk add --no-cache gcc g++; \
        fi; \
    fi

# Install cache tool
IF PROC [ "${CACHE_TOOL}" = "ccache" ]
    RUN if command -v apt-get >/dev/null 2>&1; then \
            apt-get install -y ccache; \
        elif command -v apk >/dev/null 2>&1; then \
            apk add --no-cache ccache; \
        fi && \
        mkdir -p /root/.ccache
ELSE IF PROC [ "${CACHE_TOOL}" = "sccache" ]
    RUN curl -L https://github.com/mozilla/sccache/releases/download/v0.7.4/sccache-v0.7.4-x86_64-unknown-linux-musl.tar.gz | \
        tar xz -C /usr/local/bin --strip-components=1 && \
        chmod +x /usr/local/bin/sccache
ELSE IF PROC [ "${CACHE_TOOL}" = "distcc" ]
    RUN if command -v apt-get >/dev/null 2>&1; then \
            apt-get install -y distcc; \
        elif command -v apk >/dev/null 2>&1; then \
            apk add --no-cache distcc; \
        fi
ENDIF

# Install analysis tools
IF PROC [ "${ANALYSIS_TOOL}" = "clang-tidy" ]
    RUN if command -v apt-get >/dev/null 2>&1; then \
            apt-get install -y clang-tidy; \
        elif command -v apk >/dev/null 2>&1; then \
            apk add --no-cache clang-extra-tools; \
        fi
ELSE IF PROC [ "${ANALYSIS_TOOL}" = "cppcheck" ]
    RUN if command -v apt-get >/dev/null 2>&1; then \
            apt-get install -y cppcheck; \
        elif command -v apk >/dev/null 2>&1; then \
            apk add --no-cache cppcheck; \
        fi
ELSE IF PROC [ "${ANALYSIS_TOOL}" = "infer" ]
    RUN curl -L https://github.com/facebook/infer/releases/download/v1.1.0/infer-linux64-v1.1.0.tar.xz | \
        tar xJ -C /opt && \
        ln -s /opt/infer-linux64-v1.1.0/bin/infer /usr/local/bin/infer
ENDIF

# Install Bear for compilation database generation
RUN if command -v apt-get >/dev/null 2>&1; then \
        apt-get install -y bear 2>/dev/null || true; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache bear 2>/dev/null || true; \
    fi

# Install build system-specific tools
IF PROC [ "${BUILD_SYSTEM}" = "meson" ]
    RUN pip3 install --no-cache-dir meson
ELSE IF PROC [ "${BUILD_SYSTEM}" = "bazel" ]
    RUN curl -fsSL https://bazel.build/bazel-release.pub.gpg | apt-key add - && \
        echo "deb [arch=amd64] https://storage.googleapis.com/bazel-apt stable jdk1.8" | tee /etc/apt/sources.list.d/bazel.list && \
        apt-get update && apt-get install -y bazel
ELSE IF PROC [ "${BUILD_SYSTEM}" = "xmake" ]
    RUN bash <(curl -fsSL https://xmake.io/shget.text)
ELSE IF PROC [ "${BUILD_SYSTEM}" = "premake" ]
    RUN curl -L https://github.com/premake/premake-core/releases/download/v5.0.0-beta2/premake-5.0.0-beta2-linux.tar.gz | \
        tar xz -C /usr/local/bin
ELSE IF PROC [ "${BUILD_SYSTEM}" = "scons" ]
    RUN pip3 install --no-cache-dir scons
ELSE IF PROC [ "${BUILD_SYSTEM}" = "platformio" ]
    RUN pip3 install --no-cache-dir platformio
ENDIF

# Clean up
RUN if command -v apt-get >/dev/null 2>&1; then \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

WORKDIR /home/dexfile/app

# Set compiler environment variables
ENV CC=${COMPILER}
IF PROC [ "${COMPILER}" = "clang" ]
    ENV CXX=clang++
ELSE IF PROC [ "${COMPILER}" = "gcc" ] || [ "${COMPILER}" = "musl-gcc" ]
    ENV CXX=g++
ENDIF

# Configure cache tool
IF PROC [ "${CACHE_TOOL}" = "ccache" ]
    ENV CC="ccache ${CC}"
    ENV CXX="ccache ${CXX}"
    ENV CCACHE_DIR=/root/.ccache
ELSE IF PROC [ "${CACHE_TOOL}" = "sccache" ]
    ENV RUSTC_WRAPPER=sccache
    ENV CC="sccache ${CC}"
    ENV CXX="sccache ${CXX}"
ENDIF

# ============================================================================
# PACKAGE MANAGER STAGE
# ============================================================================
FROM base AS dependencies

# Copy package manager files
COPY conanfile.txt conanfile.py vcpkg.json vcpkg-configuration.json ./ 2>/dev/null || true
COPY cmake/Hunter/ ./cmake/Hunter/ 2>/dev/null || true
COPY buckaroo.json .buckconfig ./ 2>/dev/null || true
COPY manifest repositories.manifest ./ 2>/dev/null || true
COPY dependencies.txt .apt-packages ./ 2>/dev/null || true

# Install package managers
IF PROC [ "${PACKAGE_MANAGER}" = "conan" ]
    RUN pip3 install --no-cache-dir conan && \
        conan profile detect --force
    
    # Install dependencies
    RUN --mount=type=cache,id=conan-cache,target=/root/.conan2,sharing=locked \
        if [ -f "conanfile.txt" ]; then \
            conan install . --build=missing --output-folder=build; \
        elif [ -f "conanfile.py" ]; then \
            conan install . --build=missing --output-folder=build; \
        fi

ELSE IF PROC [ "${PACKAGE_MANAGER}" = "vcpkg" ]
    RUN git clone https://github.com/microsoft/vcpkg.git /opt/vcpkg && \
        /opt/vcpkg/bootstrap-vcpkg.sh
    
    ENV VCPKG_ROOT=/opt/vcpkg
    
    # Install dependencies
    RUN --mount=type=cache,id=vcpkg-cache,target=/root/.vcpkg,sharing=locked \
        if [ -f "vcpkg.json" ]; then \
            /opt/vcpkg/vcpkg install --x-manifest-root=.; \
        fi

ELSE IF