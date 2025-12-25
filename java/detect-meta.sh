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
