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
