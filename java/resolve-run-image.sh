#!/bin/sh
# ============================================================================
# Resolves minimal runtime image for Java applications (Future-proof)
# Inputs (env):
#   DISTRO, DISTRO_VARIANT, BUILD_NATIVE, FRAMEWORK_TYPE, JAVA_VERSION / JRE_VERSION
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
JAVA_VER="${JAVA_VERSION:-}"

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
        printf '[ERROR] JAVA_VERSION or detect_java_version() must be set\n' >&2
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
