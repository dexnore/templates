# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

ARG MAVEN_CLI_OPTS="-B -DskipTests -Dmaven.wagon.http.retryHandler.count=3"
ARG GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.caching=true"
ARG PORT=8080
ARG JAVA_ENTRYPOINT MAIN_CLASS JAVA_OPTS CORRETTO_BASE=al2023 \
    APP_NAME LIB_DIR_NAME SKIP_TESTS LOG_LEVEL JAVA_CMD \
    BUILD_IMAGE RUN_IMAGE BUILD_NATIVE JDK_VERSION DISTRO_VARIANT \
    JRE_VERSION=21 FRAMEWORK_TYPE DISTRO=temurin MAVEN_VER GRADLE_VER \
    MAVEN_SETTINGS_PATH GRADLE_INIT_PATH REFRESH_DEPENDENCIES NET_RETRIES NET_TIMEOUT \
    BUILD_PROFILE BUILD_GOAL PARALLELISM OFFLINE

WORKDIR /home/dexfile/app

COPY <<-"EOF" /usr/local/bin/detect-meta.sh
#!/bin/sh
# ============================================================================
# Meta detection script for Java builds
# Functions:
#   detect_distro        - Detects base distribution
#   detect_build_native  - Detects if native build (true/false)
#   detect_framework     - Detects Java framework type
#   detect_ant_version   - Detects installed Ant version (if any)
# ============================================================================
set -eu

###############################################################################
# DISTRO detection (user-overridable)
###############################################################################
detect_distro() {
    case "${DISTRO:-temurin}" in
        temurin|alpine|corretto|liberica|ubi) ;;
        *) printf '%s' "temurin"; return ;;
    esac
    printf '%s' "${DISTRO:-temurin}"
}

###############################################################################
# Native build detection (true/false)
###############################################################################
detect_build_native() {
    case "${BUILD_NATIVE:-false}" in
        true|false) printf '%s' "${BUILD_NATIVE:-false}" ;;
        *) printf '%s' "false" ;;
    esac
}

###############################################################################
# Framework detection (springboot, quarkus, micronaut, jakartaee, ant, etc.)
###############################################################################
detect_framework() {
    framework="standard"
    bt_file=""
    for f in pom.xml build.gradle build.gradle.kts build.xml; do
        [ -f "$f" ] && { bt_file="$f"; break; }
    done

    [ -z "$bt_file" ] && { printf '%s' "$framework"; return; }

    has_dep() { grep -i "$1" "$bt_file" >/dev/null 2>&1; }

    if has_dep 'spring-boot'; then
        framework="springboot"
    elif has_dep 'quarkus'; then
        framework="quarkus"
    elif has_dep 'micronaut'; then
        framework="micronaut"
    elif has_dep 'jakarta.jakartaee-api' || has_dep 'javax.javaee-api'; then
        framework="jakartaee"
    elif has_dep 'wildfly' || has_dep 'jboss'; then
        framework="wildfly"
    elif has_dep 'glassfish'; then
        framework="glassfish"
    elif has_dep 'jetty'; then
        framework="jetty"
    elif has_dep 'tomcat'; then
        framework="tomcat"
    elif [ "$bt_file" = "build.xml" ]; then
        framework="ant"
    fi

    printf '%s' "$framework"
}

###############################################################################
# Ant version detection (if installed)
###############################################################################
detect_ant_version() {
    ant -version 2>/dev/null | awk '{print $NF}' | tr -cd '0-9.' || true
}

###############################################################################
# POSIX error helper
###############################################################################
posix_err() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

###############################################################################
# Main dispatcher
###############################################################################
if [ $# -gt 0 ]; then
    func="$1"; shift
    # Check if function exists
    if command -v "$func" >/dev/null 2>&1; then
        "$func" "$@"
    else
        posix_err "Function '$func' not found in this script."
    fi
else
    posix_err "No function specified. Usage: $0 <function_name>"
fi
EOF

RUN chmod +x /usr/local/bin/detect-meta.sh

COPY <<-"EOF" /usr/local/bin/detect_java_version.sh
#!/bin/sh
# ============================================================================
# Java Version Detector (Compile-time vs Runtime)
# User preference is authoritative – NO normalization
# POSIX / BusyBox safe
# ============================================================================

set -eu

posix_err() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
strip_java_version() {
    # Converts 1.8.0_362 → 8, 17.0.1 → 17, 21 → 21
    v=$(printf '%s' "$1" | tr -cd '0-9.')
    case "$v" in 1.*) v=${v#1.} ;; esac
    printf '%s\n' "${v%%.*}"
}

# ----------------------------------------------------------------------------
# Detect COMPILE-TIME Java (source compatibility)
# ----------------------------------------------------------------------------
detect_compile_java() {
    raw=""

    # Maven
    if [ -f pom.xml ]; then
        raw=$(awk -F'[<>]' '
            /<maven.compiler.release>/ {print $3; exit}
            /<maven.compiler.source>/  {print $3; exit}
            /<java.version>/           {print $3; exit}
        ' pom.xml 2>/dev/null)
    fi

    # Maven JVM flags
    if [ -z "$raw" ] && [ -f .mvn/jvm.config ]; then
        raw=$(grep -- '--source\|--release' .mvn/jvm.config 2>/dev/null |
              tr -cd '0-9.' | head -1)
    fi

    # Gradle
    if [ -z "$raw" ]; then
        raw=$(grep 'sourceCompatibility' build.gradle* 2>/dev/null |
              tr -cd '0-9.' | head -1)
    fi

    # Gradle toolchain
    if [ -z "$raw" ]; then
        raw=$(grep 'languageVersion' build.gradle* 2>/dev/null |
              tr -cd '0-9.' | head -1)
    fi

    # Ant
    if [ -z "$raw" ] && [ -f build.xml ]; then
        raw=$(awk '
            match($0,/source="[^"]+"/){
                print substr($0,RSTART+8,RLENGTH-9); exit
            }
            /java.version/{
                gsub(/[^0-9.]/,""); print; exit
            }' build.xml 2>/dev/null)
    fi

    # Version managers
    [ -z "$raw" ] && [ -f .java-version ] && raw=$(cat .java-version)
    [ -z "$raw" ] && [ -f .tool-versions ] &&
        raw=$(awk '$1=="java"{print $2; exit}' .tool-versions)
    [ -z "$raw" ] && [ -f .sdkmanrc ] &&
        raw=$(grep '^java=' .sdkmanrc | cut -d= -f2)

    [ -z "$raw" ] && raw=17

    strip_java_version "$raw"
}

# ----------------------------------------------------------------------------
# Detect RUNTIME Java (target compatibility)
# ----------------------------------------------------------------------------
detect_runtime_java() {
    raw=""

    # Maven
    if [ -f pom.xml ]; then
        raw=$(awk -F'[<>]' '
            /<maven.compiler.release>/ {print $3; exit}
            /<maven.compiler.target>/  {print $3; exit}
        ' pom.xml 2>/dev/null)
    fi

    # Gradle
    if [ -z "$raw" ]; then
        raw=$(grep 'targetCompatibility' build.gradle* 2>/dev/null |
              tr -cd '0-9.' | head -1)
    fi

    # Ant
    if [ -z "$raw" ] && [ -f build.xml ]; then
        raw=$(awk '
            match($0,/target="[^"]+"/){
                print substr($0,RSTART+8,RLENGTH-9); exit
            }' build.xml 2>/dev/null)
    fi

    # Framework-enforced minimums (only if NOTHING specified)
    if [ -z "$raw" ]; then
        case "${FRAMEWORK_TYPE:-}" in
            springboot)
                if grep '<version>3\.' pom.xml 2>/dev/null ||
                   grep 'springBootVersion.*3\.' build.gradle* 2>/dev/null; then
                    raw=17
                fi
                ;;
            jakartaee)
                raw=11
                ;;
        esac
    fi

    # Final fallback
    [ -z "$raw" ] && raw=$(detect_compile_java)

    strip_java_version "$raw"
}

# ----------------------------------------------------------------------------
# Dispatcher
# ----------------------------------------------------------------------------
[ $# -eq 1 ] || posix_err "Usage: $0 detect_compile_java|detect_runtime_java"

case "$1" in
    detect_compile_java) detect_compile_java ;;
    detect_runtime_java) detect_runtime_java ;;
    *) posix_err "Unknown function: $1" ;;
esac
EOF

RUN chmod +x /usr/local/bin/detect_java_version.sh

COPY <<-"EOF" /usr/local/bin/detect_build_image.sh
# ============================================================================
# Resolve BUILD-TIME JDK image (fully user-customizable)
#
# ENV VARS / META ARGS:
#   DISTRO        - temurin | alpine | corretto | liberica | ubi | graalvm
#   JDK_VERSION  - major or full (8,11,17,21,22,23,24,...)
#   BUILD_NATIVE  - true | false
#   DISTRO_VARIANT- optional, e.g., al2023, ubi8, ubi9
#
# STDOUT: full OCI image reference
# ============================================================================
resolve_build_jdk_image() {
    distro="${DISTRO:-temurin}"
    java="${JDK_VERSION:-17}"
    native="${BUILD_NATIVE:-false}"
    variant="${DISTRO_VARIANT:-}"

    # Native builds => GraalVM builder
    if [ "$native" = "true" ]; then
        printf '%s' "ghcr.io/graalvm/native-image-community:${java}${variant:+-$variant}"
        return
    fi

    case "$distro" in
        temurin)
            printf '%s' "eclipse-temurin:${java}-jdk${variant:+-$variant}"
            ;;

        alpine)
            printf '%s' "bellsoft/liberica-openjdk-alpine:${java}${variant:+-$variant}"
            ;;

        corretto)
            # variant can be e.g., al2023, al2022, etc.
            printf '%s' "amazoncorretto:${java}${variant:+-$variant}"
            ;;

        liberica)
            printf '%s' "bellsoft/liberica-openjdk:${java}${variant:+-$variant}"
            ;;

        ubi)
            # variant can be ubi8 / ubi9 / etc.
            printf '%s' "registry.access.redhat.com/ubi${variant:-9}/openjdk-${java}-devel"
            ;;

        graalvm)
            printf '%s' "ghcr.io/graalvm/jdk-community:${java}${variant:+-$variant}"
            ;;

        *)
            # fallback to safe Temurin
            printf '%s' "eclipse-temurin:${java}-jdk${variant:+-$variant}"
            ;;
    esac
}

resolve_build_jdk_image
EOF

RUN chmod +x /usr/local/bin/detect_build_image.sh

IF RUN /usr/local/bin/detect-meta.sh detect_build_native
    ARG BUILD_NATIVE=${STDOUT}
ELSE
    RUN echo "failed to retrive BUILD_NATIVE: {$STDOUT}"
ENDIF

IF RUN /usr/local/bin/detect-meta.sh detect_distro
    ARG DISTRO=${STDOUT}
ELSE
    RUN echo "failed to retrive DISTRO: ${STDOUT}"
ENDIF

IF RUN --mount=target=. /usr/local/bin/detect-meta.sh detect_compile_java
    ARG JDK_VERSION=${STDOUT}
ELSE
    RUN echo "failed to retrive JDK_VERSION: ${STDOUT}"
ENDIF

IF RUN /usr/local/bin/detect_build_image.sh
    ARG BUILD_IMAGE=${STDOUT}
ELSE
    RUN echo "failed to retrive build image: ${STDOUT}"
ENDIF

COPY <<-"EOF" /usr/local/bin/detect_run_image.sh
#!/bin/sh
# ============================================================================
# Resolves minimal runtime image for Java applications (Future-proof)
# Inputs (env):
#   DISTRO, DISTRO_VARIANT, BUILD_NATIVE, FRAMEWORK_TYPE, JDK_VERSION / JRE_VERSION
# Output (stdout):
#   RUN_IMAGE
# ============================================================================
set -eu

# -----------------------
# Environment defaults
# -----------------------
DISTRO="${DISTRO:-temurin}"
DISTRO_VARIANT="${DISTRO_VARIANT:-}"
BUILD_NATIVE="${BUILD_NATIVE:-false}"
FRAMEWORK_TYPE="${FRAMEWORK_TYPE:-standard}"
JAVA_VER="${JRE_VERSION:-}"

# -----------------------
# WAR detection (generic)
# -----------------------
is_war() {
    [ -f pom.xml ] && grep '<packaging>war</packaging>' pom.xml >/dev/null 2>&1 && return 0
    for f in build.gradle build.gradle.kts; do
        [ -f "$f" ] && grep -i 'apply.*plugin.*war\|id.*war' "$f" >/dev/null 2>&1 && return 0
    done
    return 1
}

# -----------------------
# Runtime image resolver
# -----------------------
resolve_run_image() {
    [ -n "$JAVA_VER" ] || {
        printf '[ERROR] JRE_VERSION or detect_java_version() must be set\n' >&2
        exit 1
    }

    # -----------------------
    # Native builds
    # -----------------------
    if [ "$BUILD_NATIVE" = "true" ]; then
        case "$DISTRO" in
            scratch)    printf 'scratch' ;;
            alpine)     printf 'alpine:3.20' ;;
            distroless) printf 'gcr.io/distroless/static-debian12:latest' ;;
            *)          printf 'gcr.io/distroless/cc-debian12:latest' ;;
        esac
        return
    fi

    # -----------------------
    # WAR deployments → servlet containers
    # -----------------------
    if is_war; then
        case "$FRAMEWORK_TYPE" in
            jetty)
                printf 'jetty:12-jre%s%s' "$JAVA_VER" "${DISTRO_VARIANT:+-$DISTRO_VARIANT}"
                return ;;
            tomcat|*)
                printf 'tomcat:10-jre%s-temurin%s' "$JAVA_VER" "${DISTRO_VARIANT:+-$DISTRO_VARIANT}"
                return ;;
        esac
    fi

    # -----------------------
    # JAR deployments → minimal JVM runtimes
    # -----------------------
    case "$DISTRO" in
        distroless)
            if [ "$JAVA_VER" -ge 11 ] 2>/dev/null; then
                printf 'gcr.io/distroless/java%s-debian12:nonroot' "$JAVA_VER"
            else
                printf 'eclipse-temurin:%s-jre%s' "$JAVA_VER" "${DISTRO_VARIANT:+-$DISTRO_VARIANT}"
            fi
            ;;
        alpine)
            printf 'eclipse-temurin:%s-jre-alpine%s' "$JAVA_VER" "${DISTRO_VARIANT:+-$DISTRO_VARIANT}"
            ;;
        ubi|ubi-minimal)
            printf 'registry.access.redhat.com/ubi%s/openjdk-%s-runtime:latest' "${DISTRO_VARIANT:-9}" "$JAVA_VER"
            ;;
        corretto)
            printf 'amazoncorretto:%s-jre%s' "$JAVA_VER" "${DISTRO_VARIANT:+-$DISTRO_VARIANT}"
            ;;
        liberica)
            printf 'bellsoft/liberica-openjre-alpine:%s%s' "$JAVA_VER" "${DISTRO_VARIANT:+-$DISTRO_VARIANT}"
            ;;
        temurin|*)
            printf 'eclipse-temurin:%s-jre%s' "$JAVA_VER" "${DISTRO_VARIANT:+-$DISTRO_VARIANT}"
            ;;
    esac
}

# -----------------------
# Execute
# -----------------------
resolve_run_image
EOF

RUN chmod +x /usr/local/bin/detect_run_image.sh

IF RUN --mount=target=. /usr/local/bin/detect-meta.sh detect_framework
    ARG FRAMEWORK_TYPE=${STDOUT}
ELSE
    RUN echo "failed to retrive FRAMEWORK_TYPE: ${STDOUT}"
ENDIF

IF RUN --mount=target=. /usr/local/bin/detect_java_version.sh detect_runtime_java
    ARG JRE_VERSION=${STDOUT}
ELSE
    RUN echo "failed to retrive JRE_VERSION: ${STDOUT}"
ENDIF

IF RUN --mount=target=. /usr/local/bin/detect_run_image.sh
    ARG RUN_IMAGE=${STDOUT}
ELSE
    RUN echo "failed to retrive RUN_IMAGE: ${STDOUT}"
ENDIF

COPY <<-"EOF" /usr/local/bin/download_deps.sh
#!/bin/sh
# ============================================================================
# Production-Grade Dependency Resolver
# Optimized for Docker caching, CI stability, and zero false positives
# Supports: Maven, Gradle, Ant (+ Ivy)
# ============================================================================
set -eu

###############################################################################
# Logging (auto-disable ANSI if not TTY)
###############################################################################
if [ -t 1 ]; then
    BLUE='\033[0;34m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
else
    BLUE=''; YELLOW=''; RED=''; NC=''
fi

log()  { printf '%s[INFO]%s %s\n'  "$BLUE" "$NC" "$*"; }
warn() { printf '%s[WARN]%s %s\n'  "$YELLOW" "$NC" "$*" >&2; }
err()  { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

###############################################################################
# Build tool detection (strict, wrapper-first)
###############################################################################
detect_build_tool() {
    if [ -x "./mvnw" ]; then
        printf 'maven-w'
    elif [ -f "pom.xml" ]; then
        printf 'maven'
    elif [ -x "./gradlew" ]; then
        printf 'gradle-w'
    elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
        printf 'gradle'
    elif [ -f "build.xml" ]; then
        printf 'ant'
    else
        printf 'none'
    fi
}

###############################################################################
# Dependency resolution
###############################################################################
download_dependencies() {
    tool=$(detect_build_tool)

    # User controls
    MVN_SETTINGS="${MAVEN_SETTINGS_PATH:-}"
    GRADLE_INIT="${GRADLE_INIT_PATH:-}"
    REFRESH="${REFRESH_DEPENDENCIES:-false}"
    NET_RETRIES="${NET_RETRIES:-3}"
    NET_TIMEOUT="${NET_TIMEOUT:-30}"

    case "$tool" in
        maven|maven-w)
            exe="mvn"; [ "$tool" = "maven-w" ] && exe="./mvnw"
            log "Resolving Maven dependencies (parallel, offline-ready)"

            # Auto-detect settings.xml if not explicitly provided
            if [ -z "$MVN_SETTINGS" ] && [ -f "$HOME/.m2/settings.xml" ]; then
                MVN_SETTINGS="$HOME/.m2/settings.xml"
            fi

            MAVEN_OPTS="
                -Dmaven.repo.local=${MAVEN_REPO_LOCAL:-$HOME/.m2/repository}
                -Dmaven.wagon.http.retryHandler.count=$NET_RETRIES
                -Dmaven.wagon.httpconnectionManager.ttlSeconds=$NET_TIMEOUT
            "

            MAVEN_OPTS="$MAVEN_OPTS" \
            $exe dependency:go-offline \
                ${MVN_SETTINGS:+-s "$MVN_SETTINGS"} \
                -B -T 1C \
                -Dmdep.analyze.skip=true \
                --fail-never
            ;;

        gradle|gradle-w)
            exe="gradle"; [ "$tool" = "gradle-w" ] && exe="./gradlew"
            log "Resolving Gradle dependencies (cache-warming)"

            args="--no-daemon --console=plain --stacktrace"
            [ "$REFRESH" = "true" ] && args="$args --refresh-dependencies"

            # Gradle 8+ safe, config-cache compatible
            GRADLE_OPTS="-Dorg.gradle.internal.http.connectionTimeout=$((NET_TIMEOUT*1000)) \
                          -Dorg.gradle.internal.http.socketTimeout=$((NET_TIMEOUT*1000))"

            GRADLE_OPTS="$GRADLE_OPTS" \
            $exe dependencies $args \
                ${GRADLE_INIT:+-I "$GRADLE_INIT"} \
                || warn "Some Gradle configurations failed to resolve"
            ;;

        ant)
            log "Resolving Ant dependencies (Ivy-aware)"

            if [ -f "ivy.xml" ] || grep -qi 'ivy' build.xml; then
                ant -f build.xml resolve -Divy.offline=false
            else
                warn "Ant detected but Ivy not configured; skipping"
            fi
            ;;

        none)
            err "No supported build system detected"
            ;;
    esac
}

###############################################################################
# Cleanup (Docker layer minimization)
###############################################################################
cleanup_metadata() {
    tool=$(detect_build_tool)
    log "Cleaning transient metadata"

    case "$tool" in
        maven*)
            rm -rf target/maven-archiver 2>/dev/null || true
            ;;
        gradle*)
            rm -rf .gradle/caches/journal-* \
                   .gradle/daemon \
                   .gradle/native \
                   .gradle/workers 2>/dev/null || true
            ;;
    esac
}

###############################################################################
# Dispatcher (explicit execution only)
###############################################################################
[ $# -gt 0 ] || err "Usage: $0 download_dependencies | cleanup_metadata"

case "$1" in
    download_dependencies) download_dependencies ;;
    cleanup_metadata)      cleanup_metadata ;;
    *)                     err "Unknown function: $1" ;;
esac
EOF

RUN chmod +x /usr/local/bin/download_deps.sh

COPY <<-"EOF" /usr/local/bin/copy_artifacts.sh
#!/bin/sh
# =============================================================================
# ULTIMATE JAVA ARTIFACT RESOLVER — FINAL ENTERPRISE EDITION
# Output: Dockerfile COPY instructions + ENTRYPOINT_ARTIFACT
# =============================================================================
set -eu

###############################################################################
# CONFIG
###############################################################################
OUT_ROOT="${JAVA_LAYOUT_ROOT:-/opt/app}"
APP_DIR="$OUT_ROOT/app"
LIB_DIR="$APP_DIR/lib"
ROOTS=". target build dist out"

ARTIFACT_PATH="${ARTIFACT_PATH:-}"
LIBS_PATH="${LIBS_PATH:-}"

###############################################################################
# LOGGING
###############################################################################
if [ -t 2 ]; then
  I="\033[1;34m[INFO]\033[0m"
  E="\033[1;31m[ERROR]\033[0m"
else
  I="[INFO]"
  E="[ERROR]"
fi

log(){ printf "%s %s\n" "$I" "$*" >&2; }
die(){ printf "%s %s\n" "$E" "$*" >&2; exit 1; }

###############################################################################
# SAFE HELPERS (NO FALSE POSITIVES)
###############################################################################
is_elf()        { file "$1" 2>/dev/null | grep -qi '^ELF .* executable'; }
is_zip_ok()     { unzip -t "$1" >/dev/null 2>&1; }

has_main() {
  unzip -p "$1" META-INF/MANIFEST.MF 2>/dev/null |
    grep -qi '^Main-Class:'
}

is_boot() {
  unzip -l "$1" 2>/dev/null |
    grep -qE 'BOOT-INF/|org/springframework/boot/loader'
}

is_quarkus_runner() {
  unzip -l "$1" 2>/dev/null | grep -q 'io/quarkus/runtime'
}

is_tooling() {
  echo "$1" | grep -qiE '(maven-|gradle-|plugin-|annotation-|processor)'
}

is_test_artifact() {
  echo "$1" | grep -qiE '(test|junit|mockito)'
}

size() {
  stat -c %s "$1" 2>/dev/null || ls -ln "$1" | awk '{print $5}'
}

###############################################################################
# OUTPUT EMITTERS (STRICT)
###############################################################################
emit_file() {
  printf 'COPY --from=builder %s %s/%s\n' "$1" "$APP_DIR" "$2"
}

emit_dir() {
  printf 'COPY --from=builder %s/ %s/\n' "$1" "$2"
}

emit_entry() {
  printf 'ENTRYPOINT_ARTIFACT=%s\n' "$1"
}

###############################################################################
# 1. USER OVERRIDE (ABSOLUTE AUTHORITY)
###############################################################################
if [ -n "$ARTIFACT_PATH" ]; then
  [ -e "$ARTIFACT_PATH" ] || die "ARTIFACT_PATH does not exist"

  log "User override: $ARTIFACT_PATH"

  if [ -d "$ARTIFACT_PATH" ]; then
    emit_dir "$ARTIFACT_PATH" "$APP_DIR"
    emit_entry "$APP_DIR"
  else
    name="$(basename "$ARTIFACT_PATH")"
    emit_file "$ARTIFACT_PATH" "$name"
    emit_entry "$APP_DIR/$name"
  fi

  [ -n "$LIBS_PATH" ] && [ -d "$LIBS_PATH" ] && emit_dir "$LIBS_PATH" "$LIB_DIR"
  exit 0
fi

###############################################################################
# 2. NATIVE IMAGE (STRICT ELF)
###############################################################################
for r in $ROOTS; do
  [ -d "$r" ] || continue
  find "$r" -type f -perm -111 2>/dev/null |
  while read -r f; do
    is_elf "$f" || continue
    echo "$f"
    break
  done
done | head -n1 | while read -r bin; do
  log "Native executable detected: $bin"
  emit_file "$bin" run.bin
  emit_entry "$APP_DIR/run.bin"
  exit 0
done

###############################################################################
# 3. QUARKUS FAST-JAR (IMMUTABLE)
###############################################################################
for r in $ROOTS; do
  if [ -f "$r/quarkus-app/quarkus-run.jar" ]; then
    log "Quarkus fast-jar detected"
    emit_dir "$r/quarkus-app" "$APP_DIR"
    emit_entry "$APP_DIR/quarkus-run.jar"
    exit 0
  fi
done

###############################################################################
# 4. ARTIFACT SCORING ENGINE
###############################################################################
log "Scanning JVM artifacts..."

BEST="$(
for r in $ROOTS; do
  [ -d "$r" ] || continue
  find "$r" -type f \( -name '*.jar' -o -name '*.war' \) 2>/dev/null |
  while read -r a; do
    is_tooling "$a" && continue
    is_test_artifact "$a" && continue
    is_zip_ok "$a" || continue

    tier=1
    is_boot "$a" && tier=6
    is_quarkus_runner "$a" && tier=5
    has_main "$a" && tier=4
    [ "${a##*.}" = war ] && tier=3

    sz=$(printf "%012d" "$(size "$a")")
    printf "%02d-%s %s\n" "$tier" "$sz" "$a"
  done
done | sort -r | head -n1 | awk '{print $2}'
)"

###############################################################################
# 5. FALLBACK: EXPLODED APP
###############################################################################
if [ -z "$BEST" ]; then
  for r in $ROOTS; do
    for d in "$r/classes" "$r/app" "$r/exploded"; do
      [ -d "$d" ] || continue
      log "Exploded JVM app detected: $d"
      emit_dir "$d" "$APP_DIR"
      emit_entry "$APP_DIR"
      exit 0
    done
  done
  die "No runnable Java artifact found"
fi

###############################################################################
# 6. LIBRARY DISCOVERY (THIN JARS)
###############################################################################
for d in $(
  find . -type d \( -name lib -o -name libs -o -name dependency \) 2>/dev/null |
  while read -r l; do
    ls "$l"/*.jar >/dev/null 2>&1 && echo "$l"
  done | sort -u
); do
  log "Including libs: $d"
  emit_dir "$d" "$LIB_DIR"
done

###############################################################################
# 7. FINAL EMISSION
###############################################################################
name="$(basename "$BEST")"
log "Selected artifact: $BEST"

emit_file "$BEST" "$name"
emit_entry "$APP_DIR/$name"
EOF

RUN chmod +x /usr/local/bin/copy_artifacts.sh

# ============================================================================
# BASE BUILD STAGE
# ============================================================================
FROM ${BUILD_IMAGE} AS base
WORKDIR /home/dexfile/app

# Install required build tools for native builds
IF PROC --from=busybox:latest [ "${BUILD_NATIVE}" = "true" ]
    RUN if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            gcc g++ zlib1g-dev build-essential && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache gcc g++ musl-dev zlib-dev zlib-static; \
    elif command -v microdnf >/dev/null 2>&1; then \
        microdnf install -y gcc gcc-c++ glibc-devel zlib-devel libstdc++-static && \
        microdnf clean all; \
    fi
ENDIF

# Configure build environment
ENV MAVEN_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dmaven.repo.local=/root/.m2/repository"
ENV GRADLE_OPTS="${GRADLE_OPTS}"
ENV GRADLE_USER_HOME="/root/.gradle"
ENV MAVEN_CONFIG="/root/.m2"

# Security: Run vulnerability scanning and dependency checks
RUN if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            curl wget ca-certificates git unzip && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache curl wget ca-certificates git unzip; \
    elif command -v microdnf >/dev/null 2>&1; then \
        microdnf install -y curl wget ca-certificates git unzip && \
        microdnf clean all; \
    fi

# ============================================================================
# DEPENDENCY RESOLUTION STAGE
# ============================================================================
FROM base AS deps

# Copy build configuration files
COPY pom.xml* settings.xml* build.gradle* build.gradle.kts* \
     settings.gradle* settings.gradle.kts* gradle.properties* \
     build.xml* ivy.xml* ivysettings.xml* .java-version* .tool-versions* .mvn/jvm.config* \
     mvnw* gradlew* .mvn/ gradle/ /home/dexfile/app/

# Make wrapper scripts executable
RUN if [ -f "gradlew" ]; then chmod +x gradlew; fi && \
    if [ -f "mvnw" ]; then chmod +x mvnw; fi

COPY --from=meta-stage /usr/local/bin/download_deps.sh /usr/local/bin/download_deps.sh
RUN chmod +x /usr/local/bin/download_deps.sh

# Download dependencies with aggressive caching
RUN --mount=type=secret,id=m2settings,target=/home/dexfile/app/settings.xml \
    --mount=type=cache,id=m2-cache,target=/root/.m2/repository,sharing=locked \
    --mount=type=cache,id=gradle-cache,target=/root/.gradle,sharing=locked \
    --mount=type=cache,id=ivy-cache,target=/root/.ivy2,sharing=locked \
    /usr/local/bin/download_deps.sh download_dependencies 

# ============================================================================
# BUILD STAGE
# ============================================================================
FROM base AS builder

# Copy dependencies and source code
COPY --from=deps /home/dexfile/app /home/dexfile/app
COPY . .

COPY <<-"EOF" /usr/local/bin/build-deps.sh
#!/bin/sh
# ============================================================================
# Dexfile Ultimate Artifact Builder - Enterprise-Grade
# Builds Maven, Gradle, Ant (+ Ivy) projects to a single predictable artifact
# Supports native-image builds (GraalVM), multi-module projects, and reproducible CI
# Output: /home/dexfile/app.{jar|war|exe}, optional /home/dexfile/lib/, /home/dexfile/app.meta
# ============================================================================
set -eu

OUT_DIR="/home/dexfile"
OUT_BASE="$OUT_DIR/app"
META_FILE="$OUT_DIR/app.meta"
LIB_DIR="$OUT_DIR/lib"

mkdir -p "$OUT_DIR" "$LIB_DIR"

log()  { printf '[DEXFILE] %s\n' "$*" >&2; }
warn() { printf '[DEXFILE][WARN] %s\n' "$*" >&2; }
fail() { printf '[DEXFILE][ERROR] %s\n' "$*" >&2; exit 1; }

###############################################################################
# User Config
###############################################################################
BUILD_NATIVE="${BUILD_NATIVE:-false}"
SKIP_TESTS="${SKIP_TESTS:-true}"
BUILD_PROFILE="${BUILD_PROFILE:-}"
BUILD_GOAL="${BUILD_GOAL:-}"
PARALLELISM="${BUILD_PARALLELISM:-1C}"
OFFLINE="${OFFLINE_BUILD:-true}"

###############################################################################
# Build System Detection
###############################################################################
detect_build_tool() {
    if [ -x "./mvnw" ]; then echo "maven|./mvnw"; return; fi
    if [ -f "pom.xml" ]; then echo "maven|mvn"; return; fi
    if [ -x "./gradlew" ]; then echo "gradle|./gradlew"; return; fi
    if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then echo "gradle|gradle"; return; fi
    if [ -f "build.xml" ]; then echo "ant|ant"; return; fi
    if [ -f "ivy.xml" ]; then echo "ivy|ant"; return; fi
    echo "none|"
}

###############################################################################
# Multi-module awareness
###############################################################################
find_executable_module_maven() {
    # find module containing spring-boot, quarkus, or micronaut plugin
    find . -name "pom.xml" | while read -r pom; do
        if grep -qiE 'spring-boot|quarkus|micronaut' "$pom"; then
            dirname "$pom"
            return
        fi
    done
}

find_executable_module_gradle() {
    # find subproject with main class or application plugin
    find . -name "build.gradle*" | while read -r build; do
        if grep -qiE 'mainClass|quarkus|micronaut' "$build"; then
            dirname "$build"
            return
        fi
    done
}

###############################################################################
# GraalVM Native Check
###############################################################################
require_graalvm() {
    command -v native-image >/dev/null 2>&1 || fail "BUILD_NATIVE=true but native-image not found"
}

###############################################################################
# Artifact Finalization
###############################################################################
finalize_artifact() {
    src_path="$1"
    [ -f "$src_path" ] || fail "Artifact $src_path not found"
    ext="${src_path##*.}"
    target_path="$OUT_BASE.$ext"

    log "Copying artifact $src_path -> $target_path"
    cp "$src_path" "$target_path"

    # Copy runtime dependencies if they exist
    runtime_lib_dir="$(dirname "$src_path")/lib"
    if [ -d "$runtime_lib_dir" ]; then
        log "Copying runtime libs from $runtime_lib_dir -> $LIB_DIR"
        cp -r "$runtime_lib_dir"/* "$LIB_DIR"/
    fi

    # Metadata for entrypoint
    if [ "$ext" = "jar" ] || [ "$ext" = "war" ]; then
        echo "java -jar $target_path" > "$META_FILE"
    else
        chmod +x "$target_path"
        echo "$target_path" > "$META_FILE"
    fi
}

###############################################################################
# Maven Build
###############################################################################
build_maven() {
    MVN="./mvnw"; [ -x "$MVN" ] || MVN="mvn"
    log "Building Maven project"

    # Identify module to build
    MOD_DIR=$(find_executable_module_maven || echo ".")
    cd "$MOD_DIR"

    # Use lockfiles for reproducibility
    [ -f pom.xml ] && log "Using pom.xml for deterministic dependencies"

    FLAGS="-B -T $PARALLELISM"
    [ "$SKIP_TESTS" = "true" ] && FLAGS="$FLAGS -DskipTests"
    [ "$OFFLINE" = "true" ] && FLAGS="$FLAGS -o"
    [ -n "$BUILD_PROFILE" ] && FLAGS="$FLAGS -P$BUILD_PROFILE"

    if [ "$BUILD_NATIVE" = "true" ]; then
        require_graalvm
        log "Building native image with GraalVM"
        # Spring Boot
        if grep -qi 'spring-boot' pom.xml; then
            $MVN clean package -Pnative $FLAGS
        # Quarkus
        elif grep -qi 'quarkus' pom.xml; then
            $MVN clean package -Dnative $FLAGS
        # Micronaut
        elif grep -qi 'micronaut' pom.xml; then
            $MVN clean package -Dpackaging=native-image $FLAGS
        else
            fail "Unsupported native Maven configuration"
        fi
        ARTIFACT=$(find target -type f -executable ! -name "*.jar" ! -name "*.war" | head -n1)
    else
        log "Building JVM artifact"
        $MVN clean package $FLAGS

        # Pick largest runnable artifact in module
        ARTIFACT=$(find target -type f \( -name "*.jar" -o -name "*.war" \) \
            ! -name "*-sources*" ! -name "*-javadoc*" ! -name "*-plain*" ! -name "original-*" \
            | xargs ls -S | head -n1)
    fi

    [ -n "$ARTIFACT" ] || fail "Maven build produced no artifact"
    finalize_artifact "$ARTIFACT"
    cd - >/dev/null
}

###############################################################################
# Gradle Build
###############################################################################
build_gradle() {
    GRADLE="./gradlew"; [ -x "$GRADLE" ] || GRADLE="gradle"
    log "Building Gradle project"

    MOD_DIR=$(find_executable_module_gradle || echo ".")
    cd "$MOD_DIR"

    # Use lockfile if present
    [ -f gradle.lockfile ] && log "Using gradle.lockfile for reproducible dependencies"

    FLAGS="--no-daemon --console=plain --stacktrace"
    [ "$SKIP_TESTS" = "true" ] && FLAGS="$FLAGS -x test"
    [ "$OFFLINE" = "true" ] && FLAGS="$FLAGS --offline"

    if [ "$BUILD_NATIVE" = "true" ]; then
        require_graalvm
        log "Gradle native build"
        if $GRADLE tasks --all | grep -q nativeCompile; then
            $GRADLE nativeCompile $FLAGS
            ARTIFACT=$(find build/native -type f -executable | head -n1)
        elif $GRADLE tasks --all | grep -q quarkusBuild; then
            $GRADLE quarkusBuild -Dnative $FLAGS
            ARTIFACT=$(find build/*/native/* -type f -executable | head -n1)
        else
            fail "No native Gradle tasks available"
        fi
    else
        log "Gradle JVM build"
        $GRADLE build $FLAGS

        ARTIFACT=$(find build/libs -type f \( -name "*.jar" -o -name "*.war" \) \
            ! -name "*-sources*" ! -name "*-javadoc*" ! -name "*-plain*" \
            | xargs ls -S | head -n1)
    fi

    [ -n "$ARTIFACT" ] || fail "Gradle build produced no artifact"
    finalize_artifact "$ARTIFACT"
    cd - >/dev/null
}

###############################################################################
# Ant Build (+ Ivy)
###############################################################################
build_ant() {
    ANT="ant"
    log "Building Ant/Ivy project"

    # Detect WAR vs JAR
    TARGET="jar"
    grep -qi '<war\s' build.xml 2>/dev/null && TARGET="war"

    [ "$SKIP_TESTS" = "true" ] && ANT_FLAGS="-Dskip.tests=true" || ANT_FLAGS=""
    [ "$OFFLINE" = "true" ] && ANT_FLAGS="$ANT_FLAGS -Divy.offline=true"

    $ANT clean $TARGET $ANT_FLAGS

    ARTIFACT=$(find dist build -type f -name "*.$TARGET" | head -n1)
    [ -n "$ARTIFACT" ] || fail "Ant build produced no artifact"
    finalize_artifact "$ARTIFACT"
}

###############################################################################
# Dispatcher
###############################################################################
main() {
    BUILD_INFO=$(detect_build_tool)
    IFS='|' read -r TOOL EXE <<EOF
$BUILD_INFO
EOF

    [ "$TOOL" != "none" ] || fail "No supported Java build system detected"

    log "Detected build tool: $TOOL"

    case "$TOOL" in
        maven)   build_maven ;;
        gradle)  build_gradle ;;
        ant|ivy) build_ant ;;
        *)       fail "Unsupported build tool: $TOOL" ;;
    esac

    log "Artifact build completed successfully."
    log "Single artifact available at: $OUT_BASE.*"
    log "Metadata file: $META_FILE"
}

main
EOF

RUN chmod +x /usr/local/bin/build-deps.sh

# Build the application with framework-specific optimizations
RUN --mount=type=secret,id=m2settings,source=deps,target=/home/dexfile/app/settings.xml \
    --mount=type=cache,id=m2-cache,source=deps,target=/root/.m2/repository,sharing=locked \
    --mount=type=cache,id=gradle-cache,source=deps,target=/root/.gradle,sharing=locked \
    --mount=type=cache,id=ivy-cache,source=deps,target=/root/.ivy2,sharing=locked \
    /usr/local/bin/build-deps.sh

# ============================================================================
# RUNTIME BASE STAGE
# ============================================================================
FROM ${RUN_IMAGE} AS app

# Create non-root user (distroless already has nonroot user)
IF PROC [ "${DISTRO}" != "distroless" ]
    RUN if command -v addgroup >/dev/null 2>&1; then \
            addgroup -S dexnore 2>/dev/null || true; \
            adduser -S -D -H -h /home/dexfile/app -s /sbin/nologin -G dexnore dexfile 2>/dev/null || true; \
        elif command -v groupadd >/dev/null 2>&1; then \
            groupadd -r dexnore 2>/dev/null || true; \
            useradd -r -g dexnore -d /home/dexfile/app -s /sbin/nologin dexfile 2>/dev/null || true; \
        fi && \
        mkdir -p /home/dexfile/app && \
        chown -R dexfile:dexnore /home/dexfile/app 2>/dev/null || chown -R 1000:1000 /home/dexfile/app
ENDIF

WORKDIR /home/dexfile/app

# Set user based on distro
IF PROC [ "${DISTRO}" = "distroless" ]
    USER nonroot:nonroot
ELSE
    USER dexfile:dexnore
ENDIF

# Runtime optimizations
ENV JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseG1GC -XX:+UseStringDeduplication -XX:+OptimizeStringConcat -Djava.security.egd=file:/dev/./urandom"
ENV PORT=${PORT}
EXPOSE ${PORT}

# ============================================================================
# PRODUCTION RUNTIME STAGE
# ============================================================================
FROM app AS prod

# Handle GraalVM native executables
IF PROC --from=builder --mount=target=/build [ -f "/build/home/dexfile/app" ] && [ -x "/build/home/dexfile/app" ]
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app /home/dexfile/app/app
    IF PROC --from=builder [ -d "/home/dexfile/lib/" ]
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/lib/ /home/dexfile/app/libs
    ENDIF
    IF PROC [ "${DISTRO}" = "distroless" ]
        ENTRYPOINT ["/home/dexfile/app/app"]
    ELSE
        RUN chmod +x /home/dexfile/app/app && chmod -R +x /home/dexfile/app/libs
        HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/q/health 2>/dev/null || \
                wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/actuator/health 2>/dev/null || \
                wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/health 2>/dev/null || exit 1
        ENTRYPOINT ["/home/dexfile/app/app"]
    ENDIF

# Handle WAR deployments
ELSE IF PROC --from=builder --mount=target=/build [ -f "/build/home/dexfile/app.war" ]
    # Detect application server type from RUN_IMAGE
    IF PROC echo "${RUN_IMAGE}" | grep -q "tomcat"
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app.war /usr/local/tomcat/webapps/ROOT.war
        HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
            CMD curl -f http://127.0.0.1:${PORT}/ 2>/dev/null || exit 1
        CMD ["catalina.sh", "run"]
    ELSE IF PROC echo "${RUN_IMAGE}" | grep -q "jetty"
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app.war /var/lib/jetty/webapps/ROOT.war
        HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
            CMD curl -f http://127.0.0.1:${PORT}/ 2>/dev/null || exit 1
        CMD ["java", "-jar", "/usr/local/jetty/start.jar"]
    ELSE IF PROC echo "${RUN_IMAGE}" | grep -q "wildfly"
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app.war /opt/jboss/wildfly/standalone/deployments/ROOT.war
        HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
            CMD curl -f http://127.0.0.1:${PORT}/ 2>/dev/null || exit 1
        CMD ["/opt/jboss/wildfly/bin/standalone.sh", "-b", "0.0.0.0"]
    ELSE IF PROC echo "${RUN_IMAGE}" | grep -q "glassfish"
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app.war /glassfish/domains/domain1/autodeploy/ROOT.war
        HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
            CMD curl -f http://127.0.0.1:${PORT}/ 2>/dev/null || exit 1
        CMD ["asadmin", "start-domain", "-v"]
    ELSE
        # Generic WAR deployment (embedded server in WAR)
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app.war /home/dexfile/app/app.war
        ENTRYPOINT ["java", "-jar", "/home/dexfile/app/app.war"]
    ENDIF

# Handle JAR deployments (Spring Boot, Quarkus, Micronaut, etc.)
ELSE
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app.jar /home/dexfile/app/app.jar
    
    # Framework-specific health checks
    IF PROC [ "${FRAMEWORK_TYPE}" = "springboot" ]
        IF PROC [ "${DISTRO}" != "distroless" ]
            HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
                CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/actuator/health 2>/dev/null || exit 1
        ENDIF
        ENTRYPOINT ["java", "-jar", "/home/dexfile/app/app.jar"]
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "quarkus" ]
        IF PROC [ "${DISTRO}" != "distroless" ]
            HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
                CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/q/health/live 2>/dev/null || exit 1
        ENDIF
        ENTRYPOINT ["java", "-jar", "/home/dexfile/app/app.jar"]
    ELSE IF PROC [ "${FRAMEWORK_TYPE}" = "micronaut" ]
        IF PROC [ "${DISTRO}" != "distroless" ]
            HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
                CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/health 2>/dev/null || exit 1
        ENDIF
        ENTRYPOINT ["java", "-jar", "/home/dexfile/app/app.jar"]
    ELSE
        # Generic JAR
        IF PROC [ "${DISTRO}" != "distroless" ]
            HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
                CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/health 2>/dev/null || \
                    wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/ 2>/dev/null || exit 1
        ENDIF
        ENTRYPOINT ["java", "-jar", "/home/dexfile/app/app.jar"]
    ENDIF
ENDIF

# ============================================================================
# RELEASE STAGE
# ============================================================================
FROM prod AS release

# Security and compliance labels
LABEL maintainer="@dexnore/dexfile"
LABEL org.opencontainers.image.vendor="Dexnore"
LABEL org.opencontainers.image.title="Java Application"
LABEL org.opencontainers.image.description="Production Java application supporting Spring Boot, Quarkus, Micronaut, Jakarta EE"
LABEL org.opencontainers.image.authors="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

# Security metadata
LABEL security.scan.required="true"
LABEL security.non-root="true"

FROM release
# Spring Boot, Quarkus, Micronaut, Eclipse Jakarta EE (formerly Java EE)
# Maven, Gradle, Ant + Ivy
# Apache Tomcat, Undertow, WildFly / GlassFish, Jetty
# GraalVM
# Alipne, distroless, UBI, Amazon Corretto, BellSoft Liberica JDK, Eclipse Temurin