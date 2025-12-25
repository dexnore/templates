#!/bin/sh
# ============================================================================
# MINIMAL JAVA RUNTIME IMAGE RESOLVER for BusyBox/Alpine
# Supports JAR, WAR, Spring Boot, Quarkus, Micronaut, GraalVM native
# Only prints the recommended RUN_IMAGE
# ============================================================================
set -eu

DISTRO="${DISTRO:-temurin}"
CORRETTO_BASE="${CORRETTO_BASE:-al2023}"
BUILD_NATIVE="${BUILD_NATIVE:-false}"
RUNTIME_JRE_VERSION="${RUNTIME_JRE_VERSION:-}"

# Discover build descriptor
BT=""
for f in pom.xml build.gradle build.gradle.kts build.xml; do
    if [ -f "$f" ]; then
        BT="$f"
        break
    fi
done

# Detect Java version (BusyBox safe)
detect_java_version() {
    raw="${RUNTIME_JRE_VERSION:-}"

    # Check version files
    if [ -z "$raw" ]; then
        for f in .java-version .tool-versions gradle.properties; do
            [ -f "$f" ] || continue
            
            # BusyBox grep doesn't handle -E well, check patterns separately
            case "$f" in
                .tool-versions)
                    # Check for java or temurin lines
                    line=""
                    if grep '^java' "$f" >/dev/null 2>&1; then
                        line=$(grep '^java' "$f" 2>/dev/null)
                    elif grep '^temurin' "$f" >/dev/null 2>&1; then
                        line=$(grep '^temurin' "$f" 2>/dev/null)
                    fi
                    if [ -n "$line" ]; then
                        raw=$(echo "$line" | awk '{print $2}' | tr -cd '0-9.')
                    fi
                    ;;
                gradle.properties)
                    # Check both patterns
                    line=""
                    if grep 'javaVersion=' "$f" >/dev/null 2>&1; then
                        line=$(grep 'javaVersion=' "$f" 2>/dev/null)
                    elif grep 'java\.version=' "$f" >/dev/null 2>&1; then
                        line=$(grep 'java\.version=' "$f" 2>/dev/null)
                    fi
                    if [ -n "$line" ]; then
                        raw=$(echo "$line" | cut -d= -f2 | tr -cd '0-9.')
                    fi
                    ;;
                .java-version)
                    # Simple number extraction
                    raw=$(tr -cd '0-9.' < "$f" 2>/dev/null || true)
                    ;;
            esac
            [ -n "$raw" ] && break
        done
    fi

    # Build file fallback (simplified for BusyBox)
    if [ -z "$raw" ] && [ -n "$BT" ]; then
        case "$BT" in
            pom.xml)
                # Check patterns separately
                line=""
                if grep '<java\.version>' "$BT" >/dev/null 2>&1; then
                    line=$(grep '<java\.version>' "$BT" 2>/dev/null)
                elif grep '<maven\.compiler\.release>' "$BT" >/dev/null 2>&1; then
                    line=$(grep '<maven\.compiler\.release>' "$BT" 2>/dev/null)
                fi
                if [ -n "$line" ]; then
                    raw=$(echo "$line" | sed 's/.*>\([0-9][0-9.]*\)<.*/\1/' 2>/dev/null || true)
                fi
                ;;
            build.gradle*)
                # Check both patterns
                line=""
                if grep -i 'sourceCompatibility' "$BT" >/dev/null 2>&1; then
                    line=$(grep -i 'sourceCompatibility' "$BT" 2>/dev/null)
                elif grep -i 'targetCompatibility' "$BT" >/dev/null 2>&1; then
                    line=$(grep -i 'targetCompatibility' "$BT" 2>/dev/null)
                fi
                if [ -n "$line" ]; then
                    raw=$(echo "$line" | tr -cd '0-9.')
                fi
                ;;
        esac
    fi

    # Normalize: 1.8 -> 8, keep major version
    if [ -n "$raw" ]; then
        # Remove leading "1." if present
        case "$raw" in
            1.*) raw=$(echo "$raw" | cut -c3-) ;;
        esac
        # Keep only major version
        clean=$(echo "$raw" | cut -d. -f1)
    else
        clean=""
    fi
    
    # Default to 17
    case "$clean" in
        ""|*[!0-9]*) clean="17" ;;
    esac

    printf '%s' "$clean"
}

JAVA_VER=$(detect_java_version)

# WAR/JAR detection
is_war() {
    # Check Maven
    if [ -f "pom.xml" ] && grep '<packaging>war</packaging>' pom.xml >/dev/null 2>&1; then
        return 0
    fi
    
    # Check Gradle
    for f in build.gradle build.gradle.kts; do
        if [ -f "$f" ] && grep -i 'apply.*plugin.*war\|id.*war' "$f" >/dev/null 2>&1; then
            return 0
        fi
    done
    
    return 1
}

# Framework detection helpers (BusyBox safe)
has_dep() {
    [ -n "$BT" ] && grep -i "$1" "$BT" >/dev/null 2>&1
    return $?
}

is_springboot() {
    has_dep 'spring-boot-starter'
}

is_quarkus() {
    # Check Maven or Gradle patterns separately
    if has_dep 'quarkus-maven-plugin' || has_dep 'io.quarkus' || has_dep 'quarkus-gradle-plugin'; then
        return 0
    fi
    return 1
}

is_micronaut() {
    if has_dep 'micronaut-bom' || has_dep 'io.micronaut' || has_dep 'micronaut-gradle-plugin'; then
        return 0
    fi
    return 1
}

# Check if has native build tools
is_native_build() {
    if [ "$BUILD_NATIVE" = "true" ]; then
        return 0
    fi
    
    # Check for native build indicators
    if [ -n "$BT" ]; then
        if grep -i 'native-maven-plugin' "$BT" >/dev/null 2>&1 || \
           grep -i 'org.graalvm.buildtools' "$BT" >/dev/null 2>&1 || \
           grep -i 'quarkus.package.type.*native' "$BT" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Resolve specialized minimal runtime image
resolve_image() {
    # GraalVM native image - absolute minimal
    if is_native_build; then
        case "$DISTRO" in
            scratch)    echo "scratch" ;;
            distroless) echo "gcr.io/distroless/static-debian12:latest" ;;
            alpine)     echo "alpine:3.20" ;;
            *)          echo "gcr.io/distroless/cc-debian12:latest" ;;
        esac
        return
    fi

    # WAR apps - minimal server images
    if is_war; then
        # Spring Boot WAR - use JRE (Undertow/Tomcat embedded)
        if is_springboot; then
            case "$DISTRO" in
                alpine)     printf 'eclipse-temurin:%s-jre-alpine\n' "$JAVA_VER" ;;
                distroless)
                    if [ "$JAVA_VER" -ge 11 ] 2>/dev/null; then
                        printf 'gcr.io/distroless/java%s-debian12:nonroot\n' "$JAVA_VER"
                    else
                        printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER"
                    fi
                    ;;
                *)          printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER" ;;
            esac
        # Jetty WAR
        elif has_dep 'jetty'; then
            case "$DISTRO" in
                alpine) printf 'jetty:12-jre%s-alpine\n' "$JAVA_VER" ;;
                *)      printf 'jetty:12-jre%s\n' "$JAVA_VER" ;;
            esac
        # Tomcat WAR
        elif has_dep 'tomcat'; then
            case "$DISTRO" in
                alpine) printf 'tomcat:10-jre%s-temurin-alpine\n' "$JAVA_VER" ;;
                *)      printf 'tomcat:10-jre%s-temurin\n' "$JAVA_VER" ;;
            esac
        # Default WAR - minimal JRE
        else
            case "$DISTRO" in
                alpine)     printf 'eclipse-temurin:%s-jre-alpine\n' "$JAVA_VER" ;;
                distroless)
                    if [ "$JAVA_VER" -ge 11 ] 2>/dev/null; then
                        printf 'gcr.io/distroless/java%s-debian12:nonroot\n' "$JAVA_VER"
                    else
                        printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER"
                    fi
                    ;;
                *)          printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER" ;;
            esac
        fi
        return
    fi

    # Framework-specific JAR images
    if is_springboot; then
        # Spring Boot - JRE only (embedded server)
        case "$DISTRO" in
            alpine)     printf 'eclipse-temurin:%s-jre-alpine\n' "$JAVA_VER" ;;
            distroless)
                if [ "$JAVA_VER" -ge 11 ] 2>/dev/null; then
                    printf 'gcr.io/distroless/java%s-debian12:nonroot\n' "$JAVA_VER"
                else
                    printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER"
                fi
                ;;
            *)          printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER" ;;
        esac
        return
    fi

    if is_quarkus; then
        # Quarkus - optimized for Red Hat images if available
        case "$DISTRO" in
            alpine)     printf 'eclipse-temurin:%s-jre-alpine\n' "$JAVA_VER" ;;
            ubi*)       printf 'registry.access.redhat.com/ubi9/openjdk-%s-runtime:latest\n' "$JAVA_VER" ;;
            distroless)
                if [ "$JAVA_VER" -ge 11 ] 2>/dev/null; then
                    printf 'gcr.io/distroless/java%s-debian12:nonroot\n' "$JAVA_VER"
                else
                    printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER"
                fi
                ;;
            *)          printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER" ;;
        esac
        return
    fi

    if is_micronaut; then
        # Micronaut - standard JRE
        case "$DISTRO" in
            alpine)     printf 'eclipse-temurin:%s-jre-alpine\n' "$JAVA_VER" ;;
            distroless)
                if [ "$JAVA_VER" -ge 11 ] 2>/dev/null; then
                    printf 'gcr.io/distroless/java%s-debian12:nonroot\n' "$JAVA_VER"
                else
                    printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER"
                fi
                ;;
            *)          printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER" ;;
        esac
        return
    fi

    # Default JARs - smallest possible runtime
    case "$DISTRO" in
        scratch)
            # Only for native binaries
            echo "scratch"
            ;;
        distroless)
            # Minimal secure runtime
            if [ "$JAVA_VER" -ge 11 ] 2>/dev/null; then
                printf 'gcr.io/distroless/java%s-debian12:nonroot\n' "$JAVA_VER"
            else
                printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER"
            fi
            ;;
        alpine)
            # Small Alpine-based JRE
            printf 'eclipse-temurin:%s-jre-alpine\n' "$JAVA_VER"
            ;;
        ubi-micro)
            # Red Hat absolute minimal (~30MB)
            echo 'registry.access.redhat.com/ubi9/ubi-micro:latest'
            ;;
        ubi-minimal|ubi)
            # Red Hat minimal with Java
            printf 'registry.access.redhat.com/ubi9/openjdk-%s-runtime:latest\n' "$JAVA_VER"
            ;;
        corretto)
            # Amazon Corretto JRE
            printf 'amazoncorretto:%s-jre\n' "$JAVA_VER"
            ;;
        liberica)
            # BellSoft Liberica Alpine JRE
            printf 'bellsoft/liberica-openjre-alpine:%s\n' "$JAVA_VER"
            ;;
        temurin)
            # Standard Eclipse Temurin JRE
            printf 'eclipse-temurin:%s-jre\n' "$JAVA_VER"
            ;;
        *)
            # Default to smallest available
            printf 'eclipse-temurin:%s-jre-alpine\n' "$JAVA_VER"
            ;;
    esac
}

# Output recommended RUN_IMAGE
resolve_image