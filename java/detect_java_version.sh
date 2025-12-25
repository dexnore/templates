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
