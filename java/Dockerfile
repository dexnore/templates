# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

ARG MAVEN_CLI_OPTS="-B -DskipTests -Dmaven.wagon.http.retryHandler.count=3"
ARG GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.caching=true"
ARG PORT=8080
ARG JAVA_ENTRYPOINT MAIN_CLASS JAVA_OPTS CORRETTO_BASE=al2023 \
    APP_NAME LIB_DIR_NAME SKIP_TESTS LOG_LEVEL JAVA_CMD \
    BUILD_IMAGE RUN_IMAGE BUILD_NATIVE=false JDK_VERSION \
    JRE_VERSION=21 FRAMEWORK_TYPE DISTRO=temurin MAVEN_VER GRADLE_VER

WORKDIR /home/dexfile/app

IF PROC --from=busybox:latest sh -eux <<EOF
DISTRO="${DISTRO:-temurin}"
CORRETTO_BASE="${CORRETTO_BASE:-al2023}"
BUILD_NATIVE="${BUILD_NATIVE:-false}"
JDK_VERSION="${JDK_VERSION:-}"
MAVEN_VER="3.9"
GRADLE_VER="8"

# Detect build file
BT=""
for f in pom.xml build.gradle build.gradle.kts build.xml; do
    if [ -f "$f" ]; then
        BT="$f"
        break
    fi
done

# Detect Java version from env, version files, or build files
detect_java_version() {
    raw="${JDK_VERSION:-}"

    # Check version files
    if [ -z "$raw" ]; then
        for f in .java-version .tool-versions gradle.properties; do
            [ -f "$f" ] || continue
            case "$f" in
                .tool-versions)
                    # BusyBox grep doesn't handle -E well, use multiple calls
                    line=""
                    if grep '^java' "$f" >/dev/null 2>&1; then
                        line=$(grep '^java' "$f" 2>/dev/null)
                    elif grep '^temurin' "$f" >/dev/null 2>&1; then
                        line=$(grep '^temurin' "$f" 2>/dev/null)
                    fi
                    if [ -n "$line" ]; then
                        # Use awk to extract second field, tr to keep only numbers/dots
                        raw=$(echo "$line" | awk '{print $2}' | tr -cd '0-9.')
                    fi
                    ;;
                gradle.properties)
                    # Check both patterns separately for BusyBox
                    line=""
                    if grep 'java\.version=' "$f" >/dev/null 2>&1; then
                        line=$(grep 'java\.version=' "$f" 2>/dev/null)
                    elif grep 'javaVersion=' "$f" >/dev/null 2>&1; then
                        line=$(grep 'javaVersion=' "$f" 2>/dev/null)
                    fi
                    if [ -n "$line" ]; then
                        raw=$(echo "$line" | cut -d= -f2 | tr -cd '0-9.')
                    fi
                    ;;
            esac
            [ -n "$raw" ] && break
        done
    fi

    # Build file fallback
    if [ -z "$raw" ] && [ -n "$BT" ]; then
        case "$BT" in
            pom.xml)
                # Check each pattern separately
                line=""
                if grep '<java\.version>' "$BT" >/dev/null 2>&1; then
                    line=$(grep '<java\.version>' "$BT" 2>/dev/null | head -n 1)
                elif grep '<maven\.compiler\.source>' "$BT" >/dev/null 2>&1; then
                    line=$(grep '<maven\.compiler\.source>' "$BT" 2>/dev/null | head -n 1)
                elif grep '<maven\.compiler\.target>' "$BT" >/dev/null 2>&1; then
                    line=$(grep '<maven\.compiler\.target>' "$BT" 2>/dev/null | head -n 1)
                fi
                if [ -n "$line" ]; then
                    # Simple sed extraction for BusyBox
                    raw=$(echo "$line" | sed 's/.*>\([0-9][0-9.]*\)<.*/\1/' 2>/dev/null || echo "")
                fi
                ;;
            build.gradle|build.gradle.kts)
                # Case-insensitive search
                line=""
                if grep -i 'sourceCompatibility' "$BT" >/dev/null 2>&1; then
                    line=$(grep -i 'sourceCompatibility' "$BT" 2>/dev/null | head -n 1)
                elif grep -i 'targetCompatibility' "$BT" >/dev/null 2>&1; then
                    line=$(grep -i 'targetCompatibility' "$BT" 2>/dev/null | head -n 1)
                fi
                if [ -n "$line" ]; then
                    # Extract numbers only
                    raw=$(echo "$line" | tr -cd '0-9.')
                fi
                ;;
            build.xml)
                line=$(grep '<javac' "$BT" 2>/dev/null | head -n 1)
                if [ -n "$line" ]; then
                    # Extract source attribute value
                    for word in $line; do
                        case "$word" in
                            source=*)
                                raw=$(echo "$word" | cut -d= -f2 | tr -d '"' | tr -d "'")
                                break
                                ;;
                        esac
                    done
                fi
                ;;
        esac
    fi

    # .mvn/jvm.config fallback
    if [ -z "$raw" ] && [ -f ".mvn/jvm.config" ]; then
        line=""
        if grep '--release' ".mvn/jvm.config" >/dev/null 2>&1; then
            line=$(grep '--release' ".mvn/jvm.config" 2>/dev/null | head -n 1)
        elif grep '-source' ".mvn/jvm.config" >/dev/null 2>&1; then
            line=$(grep '-source' ".mvn/jvm.config" 2>/dev/null | head -n 1)
        elif grep '-target' ".mvn/jvm.config" >/dev/null 2>&1; then
            line=$(grep '-target' ".mvn/jvm.config" 2>/dev/null | head -n 1)
        fi
        if [ -n "$line" ]; then
            raw=$(echo "$line" | tr -cd '0-9.')
        fi
    fi

    # Normalize 1.8 -> 8, major version only
    if [ -n "$raw" ]; then
        case "$raw" in
            1.*)
                raw=$(echo "$raw" | cut -c3-)
                ;;
        esac
        # Extract major version (everything before first dot)
        clean=$(echo "$raw" | cut -d. -f1)
    else
        clean=""
    fi
    
    # Default to 17 if empty or invalid
    case "$clean" in
        ""|*[!0-9]*)
            clean="17"
            ;;
    esac

    printf '%s' "$clean"
}

JAVA_VER=$(detect_java_version)

# Detect build system version (with BusyBox-safe sed)
if [ -n "$BT" ]; then
    case "$BT" in
        pom.xml)
            if [ -f ".mvn/wrapper/maven-wrapper.properties" ]; then
                # BusyBox sed might not support -n with p flag well
                line=$(grep 'distributionUrl' ".mvn/wrapper/maven-wrapper.properties" 2>/dev/null || true)
                if [ -n "$line" ]; then
                    # Extract version: ...apache-maven-3.9.6-bin.zip
                    MAVEN_VER=$(echo "$line" | sed 's/.*maven-//' | sed 's/-bin.*//' | tr -cd '0-9.')
                fi
            fi
            ;;
        build.gradle|build.gradle.kts)
            if [ -f "gradle/wrapper/gradle-wrapper.properties" ]; then
                line=$(grep 'distributionUrl' "gradle/wrapper/gradle-wrapper.properties" 2>/dev/null || true)
                if [ -n "$line" ]; then
                    GRADLE_VER=$(echo "$line" | sed 's/.*gradle-//' | sed 's/-bin.*//' | tr -cd '0-9.')
                fi
            fi
            ;;
    esac
fi

# Resolve BUILD_IMAGE
if [ "$BUILD_NATIVE" = "true" ]; then
    printf 'ghcr.io/graalvm/native-image-community:%s-ol9\n' "$JAVA_VER"
    exit 0
fi

case "$BT" in
    pom.xml)
        case "$DISTRO" in
            alpine)   printf 'maven:%s-eclipse-temurin-%s-alpine\n' "$MAVEN_VER" "$JAVA_VER" ;;
            corretto) printf 'maven:%s-amazoncorretto-%s\n' "$MAVEN_VER" "$JAVA_VER" ;;
            liberica) printf 'bellsoft/liberica-openjdk-alpine-maven:%s\n' "$JAVA_VER" ;;
            ubi)      printf 'registry.access.redhat.com/ubi9/openjdk-%s:latest\n' "$JAVA_VER" ;;
            *)        printf 'maven:%s-eclipse-temurin-%s\n' "$MAVEN_VER" "$JAVA_VER" ;;
        esac
        ;;
    build.gradle|build.gradle.kts)
        case "$DISTRO" in
            alpine)   printf 'gradle:%s-jdk%s-alpine\n' "$GRADLE_VER" "$JAVA_VER" ;;
            corretto) printf 'gradle:%s-jdk%s-amazoncorretto\n' "$GRADLE_VER" "$JAVA_VER" ;;
            liberica) printf 'bellsoft/liberica-openjdk-alpine-gradle:%s\n' "$JAVA_VER" ;;
            ubi)      printf 'registry.access.redhat.com/ubi9/openjdk-%s:latest\n' "$JAVA_VER" ;;
            *)        printf 'gradle:%s-jdk%s\n' "$GRADLE_VER" "$JAVA_VER" ;;
        esac
        ;;
    build.xml)
        case "$DISTRO" in
            alpine)   printf 'eclipse-temurin:%s-jdk-alpine\n' "$JAVA_VER" ;;
            corretto) printf 'amazoncorretto:%s\n' "$JAVA_VER" ;;
            liberica) printf 'bellsoft/liberica-openjdk-alpine:%s\n' "$JAVA_VER" ;;
            ubi)      printf 'registry.access.redhat.com/ubi9/openjdk-%s:latest\n' "$JAVA_VER" ;;
            *)        printf 'eclipse-temurin:%s-jdk\n' "$JAVA_VER" ;;
        esac
        ;;
    *)
        printf 'eclipse-temurin:%s-jdk\n' "$JAVA_VER"
        ;;
esac
EOF
    ARG BUILD_IMAGE=${STDOUT}
ELSE
    RUN echo "${STDERR}" >&2 && exit 1
ENDIF

IF PROC --from=busybox:latest sh -eux <<EOF
DISTRO="${DISTRO:-temurin}"
CORRETTO_BASE="${CORRETTO_BASE:-al2023}"
BUILD_NATIVE="${BUILD_NATIVE:-false}"
JRE_VERSION="${JRE_VERSION:-}"

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
    raw="${JRE_VERSION:-}"

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
EOF
    ARG RUN_IMAGE=${STDOUT}
ELSE
    RUN echo "${STDERR}" >&2 && exit 1
ENDIF

# ============================================================================
# BASE BUILD STAGE
# ============================================================================
FROM ${BUILD_IMAGE} AS base
WORKDIR /home/dexfile/app

# Install required build tools for native builds
IF PROC [ "${BUILD_NATIVE}" = "true" ]
    RUN if command -v microdnf >/dev/null 2>&1; then \
            microdnf install -y gcc glibc-devel zlib-devel libstdc++-static; \
        elif command -v apk >/dev/null 2>&1; then \
            apk add --no-cache gcc musl-dev zlib-dev zlib-static; \
        elif command -v apt-get >/dev/null 2>&1; then \
            apt-get update && apt-get install -y gcc zlib1g-dev; \
        fi
ENDIF

# Configure build environment
ENV MAVEN_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dmaven.repo.local=/root/.m2/repository"
ENV GRADLE_OPTS="${GRADLE_OPTS}"
ENV GRADLE_USER_HOME="/root/.gradle"
ENV MAVEN_CONFIG="/root/.m2"

# Security: Run vulnerability scanning and dependency checks
RUN if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && apt-get upgrade -y && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
        apk upgrade --no-cache; \
    elif command -v microdnf >/dev/null 2>&1; then \
        microdnf upgrade -y && microdnf clean all; \
    fi

# ============================================================================
# DEPENDENCY RESOLUTION STAGE
# ============================================================================
FROM base AS deps

# Copy build configuration files
COPY pom.xml* settings.xml* build.gradle* build.gradle.kts* \
     settings.gradle* settings.gradle.kts* gradle.properties* \
     build.xml* ivy.xml* ivysettings.xml* \
     mvnw* gradlew* .mvn/ gradle/ /home/dexfile/app/

# Make wrapper scripts executable
RUN if [ -f "gradlew" ]; then chmod +x gradlew; fi && \
    if [ -f "mvnw" ]; then chmod +x mvnw; fi

# Download dependencies with aggressive caching
RUN --mount=type=secret,id=m2settings,target=/home/dexfile/app/settings.xml \
    --mount=type=cache,id=m2-cache,target=/root/.m2/repository,sharing=locked \
    --mount=type=cache,id=gradle-cache,target=/root/.gradle,sharing=locked \
    --mount=type=cache,id=ivy-cache,target=/root/.ivy2,sharing=locked \
    set -e; \
    if [ -f "mvnw" ]; then \
        ./mvnw ${MAVEN_CLI_OPTS} dependency:resolve dependency:resolve-plugins; \
    elif [ -f "gradlew" ]; then \
        ./gradlew ${GRADLE_OPTS} --no-daemon dependencies; \
    elif [ -f "pom.xml" ]; then \
        mvn ${MAVEN_CLI_OPTS} dependency:resolve dependency:resolve-plugins; \
    elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then \
        gradle ${GRADLE_OPTS} --no-daemon dependencies; \
    elif [ -f "build.xml" ]; then \
        if [ -f "ivy.xml" ]; then \
            ant -lib /usr/share/ant/lib resolve 2>/dev/null || echo "Ivy dependencies resolution skipped"; \
        fi; \
    fi

# ============================================================================
# BUILD STAGE
# ============================================================================
FROM base AS builder

# Copy dependencies and source code
COPY --from=deps /home/dexfile/app /home/dexfile/app
COPY . .

# Build the application with framework-specific optimizations
RUN --mount=type=secret,id=m2settings,target=/home/dexfile/app/settings.xml \
    --mount=type=cache,id=m2-cache,target=/root/.m2/repository,sharing=locked \
    --mount=type=cache,id=gradle-cache,target=/root/.gradle,sharing=locked \
    --mount=type=cache,id=ivy-cache,target=/root/.ivy2,sharing=locked \
    <<EOF
set -eu

###############################################################################
# Paths & Layout
###############################################################################

OUT="${JAVA_ENTRYPOINT:-./dexfile-artifact}"
APP_DIR="$OUT/app"
LIB_DIR="$APP_DIR/lib"
META_DIR="$OUT/meta"

mkdir -p "$APP_DIR" "$LIB_DIR" "$META_DIR"

log()  { printf '[INFO] %s\n' "$*" >&2; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

###############################################################################
# Java helpers
###############################################################################

get_main_class() {
    unzip -p "$1" META-INF/MANIFEST.MF 2>/dev/null \
        | sed -n 's/^Main-Class:[[:space:]]*//p' \
        | tr -d '\r' | sed 's/[[:space:]]*$//'
}

has_spring_boot_loader() {
    unzip -l "$1" 2>/dev/null | grep -q 'org/springframework/boot/loader'
}

is_executable() {
    [ -x "$1" ] || return 1
    file "$1" 2>/dev/null | grep -qE '(ELF|Mach-O|executable)'
}

###############################################################################
# Safe artifact selector (BusyBox-safe)
###############################################################################

pick_largest() {
    _dir="$1"
    _ext="${2:-}"

    set -f
    set -- $(find "$_dir" -type f \
        ${_ext:+-name "*.$_ext"} \
        ! -name "*-sources*.jar" \
        ! -name "*-javadoc*.jar" \
        ! -name "*-plain*.jar" \
        ! -name "*-original*.jar" \
        ! -name "*-thin*.jar" \
        ! -name "*test*.jar" \
        ! -name "*.xml" ! -name "*.pom" ! -name "*.sh" 2>/dev/null)
    set +f

    [ "$#" -gt 0 ] || return 1

    ls -l "$@" 2>/dev/null \
        | awk '{print $5 "\t" $NF}' \
        | sort -nr \
        | head -1 \
        | cut -f2
}

###############################################################################
# Build tool detection
###############################################################################

BT=""
if   [ -f "./mvnw" ]; then BT="./mvnw"
elif [ -f "pom.xml" ]; then BT="mvn"
elif [ -f "./gradlew" ]; then BT="./gradlew"
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then BT="gradle"
elif [ -f "build.xml" ]; then BT="ant"
else
    err "No supported Java build system detected"
fi

log "Build tool: $BT"
case "$BT" in ./*) chmod +x "$BT" ;; esac

###############################################################################
# Build execution
###############################################################################

case "${BT##*/}" in
    mvnw|mvn)
        CMD="$BT"
        if [ "${BUILD_NATIVE:-false}" = "true" ]; then
            $CMD clean package -Pnative -DskipTests -B
            BIN="$(pick_largest target "")" || err "Native build produced nothing"
            is_executable "$BIN" || err "Native artifact is not executable"
            cp "$BIN" "$APP_DIR/app"
            echo "native" > "$META_DIR/type"
            exit 0
        fi
        $CMD clean package -DskipTests -B
        ;;
    gradlew|gradle)
        CMD="$BT"
        if [ "${BUILD_NATIVE:-false}" = "true" ]; then
            $CMD --no-daemon nativeCompile
            BIN="$(pick_largest build/native "" || pick_largest target "")" \
                || err "Native build produced nothing"
            is_executable "$BIN" || err "Native artifact is not executable"
            cp "$BIN" "$APP_DIR/app"
            echo "native" > "$META_DIR/type"
            exit 0
        fi
        $CMD --no-daemon clean build -x test
        ;;
    ant)
        ant clean jar war build 2>/dev/null || ant
        ;;
esac

###############################################################################
# Artifact classification
###############################################################################

WAR="$(pick_largest . war || true)"
if [ -n "${WAR:-}" ]; then
    log "WAR detected: $(basename "$WAR")"
    cp "$WAR" "$APP_DIR/app.war"
    echo "war" > "$META_DIR/type"
    exit 0
fi

JAR="$(pick_largest . jar || true)"
[ -n "$JAR" ] || err "No JAR artifacts produced"

MAIN_CLASS="$(get_main_class "$JAR" || true)"

if has_spring_boot_loader "$JAR" || [ -n "$MAIN_CLASS" ]; then
    log "Executable JAR detected: $(basename "$JAR")"
    cp "$JAR" "$APP_DIR/app.jar"
    echo "jar" > "$META_DIR/type"
    [ -n "$MAIN_CLASS" ] && echo "$MAIN_CLASS" > "$META_DIR/main_class"
    exit 0
fi

###############################################################################
# Thin JAR fallback
###############################################################################

log "Thin JAR detected — assembling classpath"

cp "$JAR" "$APP_DIR/app.jar"

for d in target/lib target/dependency build/libs/lib build/install/*/lib; do
    if [ -d "$d" ]; then
        log "Collecting deps from $d"
        cp -L "$d"/*.jar "$LIB_DIR/" 2>/dev/null || true
    fi
done

echo "classpath" > "$META_DIR/type"
[ -n "$MAIN_CLASS" ] && echo "$MAIN_CLASS" > "$META_DIR/main_class"

###############################################################################
# Runtime launcher
###############################################################################

cat > "$APP_DIR/run.sh" << 'EOS'
#!/bin/sh
set -e
BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE"

FOUND_CLASS="$(cat ../meta/main_class 2>/dev/null || true)"
ACTUAL_MAIN="${MAIN_CLASS:-$FOUND_CLASS}"

if [ -z "$ACTUAL_MAIN" ]; then
    echo "[ERROR] Main-Class not found. Set MAIN_CLASS env var."
    exit 1
fi

exec java ${JAVA_OPTS:-} -cp "app.jar:lib/*" "$ACTUAL_MAIN" "$@"
EOS

chmod +x "$APP_DIR/run.sh"
log "Build complete. Type: $(cat "$META_DIR/type")"
EOF

# Verify artifact was created
RUN ls -lah ./dexfile-artifact/ && \
    ([ -f "./dexfile-artifact/app" ] || [ -f "./dexfile-artifact/app.jar" ] || [ -f "./dexfile-artifact/app.war" ]) || \
    (echo "ERROR: No artifact found after build" >&2 && exit 1)

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
IF PROC --from=builder --mount=target=/build [ -f "/build/home/dexfile/app/dexfile-artifact/app" ] && [ -x "/build/home/dexfile/app/dexfile-artifact/app" ]
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dexfile-artifact/app /home/dexfile/app/app
    IF PROC [ "${DISTRO}" = "distroless" ]
        ENTRYPOINT ["/home/dexfile/app/app"]
    ELSE
        RUN chmod +x /home/dexfile/app/app
        HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/q/health 2>/dev/null || \
                wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/actuator/health 2>/dev/null || \
                wget --no-verbose --tries=1 --spider http://127.0.0.1:${PORT}/health 2>/dev/null || exit 1
        ENTRYPOINT ["/home/dexfile/app/app"]
    ENDIF

# Handle WAR deployments
ELSE IF PROC --from=builder --mount=target=/build [ -f "/build/home/dexfile/app/dexfile-artifact/app.war" ]
    # Detect application server type from RUN_IMAGE
    IF PROC echo "${RUN_IMAGE}" | grep -q "tomcat"
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dexfile-artifact/app.war /usr/local/tomcat/webapps/ROOT.war
        HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
            CMD curl -f http://127.0.0.1:${PORT}/ 2>/dev/null || exit 1
        CMD ["catalina.sh", "run"]
    ELSE IF PROC echo "${RUN_IMAGE}" | grep -q "jetty"
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dexfile-artifact/app.war /var/lib/jetty/webapps/ROOT.war
        HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
            CMD curl -f http://127.0.0.1:${PORT}/ 2>/dev/null || exit 1
        CMD ["java", "-jar", "/usr/local/jetty/start.jar"]
    ELSE IF PROC echo "${RUN_IMAGE}" | grep -q "wildfly"
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dexfile-artifact/app.war /opt/jboss/wildfly/standalone/deployments/ROOT.war
        HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
            CMD curl -f http://127.0.0.1:${PORT}/ 2>/dev/null || exit 1
        CMD ["/opt/jboss/wildfly/bin/standalone.sh", "-b", "0.0.0.0"]
    ELSE IF PROC echo "${RUN_IMAGE}" | grep -q "glassfish"
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dexfile-artifact/app.war /glassfish/domains/domain1/autodeploy/ROOT.war
        HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
            CMD curl -f http://127.0.0.1:${PORT}/ 2>/dev/null || exit 1
        CMD ["asadmin", "start-domain", "-v"]
    ELSE
        # Generic WAR deployment (embedded server in WAR)
        COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dexfile-artifact/app.war /home/dexfile/app/app.war
        ENTRYPOINT ["java", "-jar", "/home/dexfile/app/app.war"]
    ENDIF

# Handle JAR deployments (Spring Boot, Quarkus, Micronaut, etc.)
ELSE
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dexfile-artifact/app.jar /home/dexfile/app/app.jar
    
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