# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

ARG MAVEN_CLI_OPTS="-B -DskipTests -Dmaven.wagon.http.retryHandler.count=3"
ARG GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.caching=true"
ARG PORT=8080
ARG BUILD_IMAGE RUN_IMAGE BUILD_NATIVE=false RUNTIME_JRE_VERSION=21 FRAMEWORK_TYPE DISTRO=temurin

WORKDIR /home/dexfile/app

# ============================================================================
# APPLICATION SERVER IMAGE SELECTION
# ============================================================================
FUNC set_appserver_image
    # Detect preferred app server from dependencies
    IF PROC --from=busybox:latest --mount=target=. grep -q "wildfly\|jboss-eap" pom.xml build.gradle build.gradle.kts 2>/dev/null
        ARG RUN_IMAGE="quay.io/wildfly/wildfly:latest-jdk${RUNTIME_JRE_VERSION}"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "undertow" pom.xml build.gradle build.gradle.kts 2>/dev/null
        ARG RUN_IMAGE="eclipse-temurin:${RUNTIME_JRE_VERSION}-jre"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "glassfish" pom.xml build.gradle build.gradle.kts 2>/dev/null
        ARG RUN_IMAGE="glassfish/server:latest"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "jetty" pom.xml build.gradle build.gradle.kts 2>/dev/null
        IF PROC [ "${DISTRO}" = "alpine" ]
            ARG RUN_IMAGE="jetty:12-jre${RUNTIME_JRE_VERSION}-alpine"
        ELSE
            ARG RUN_IMAGE="jetty:12-jre${RUNTIME_JRE_VERSION}"
        ENDIF
    ELSE
        # Default to Tomcat
        IF PROC [ "${DISTRO}" = "alpine" ]
            ARG RUN_IMAGE="tomcat:10-jre${RUNTIME_JRE_VERSION}-temurin-alpine"
        ELSE
            ARG RUN_IMAGE="tomcat:10-jre${RUNTIME_JRE_VERSION}-temurin"
        ENDIF
    ENDIF
ENDFUNC

# ============================================================================
# RUNTIME IMAGE SELECTION
# ============================================================================
FUNC set_runtime_image
    # For GraalVM native builds, use distroless or minimal base
    IF PROC [ "${BUILD_NATIVE}" = "true" ]
        IF PROC [ "${DISTRO}" = "distroless" ]
            ARG RUN_IMAGE="gcr.io/distroless/cc-debian12:latest"
        ELSE IF PROC [ "${DISTRO}" = "alpine" ]
            ARG RUN_IMAGE="alpine:3.19"
        ELSE
            ARG RUN_IMAGE="gcr.io/distroless/base-debian12:latest"
        ENDIF
    ENDIF
    
    # For WAR files, select appropriate app server
    IF PROC [ "${FRAMEWORK_TYPE}" = "jakartaee" ] || grep -q "war" pom.xml build.gradle build.gradle.kts build.xml 2>/dev/null
        FUNC CALL set_appserver_image
    ENDIF
    
    # For standard JAR files, select JRE runtime
    IF PROC [ "${DISTRO}" = "distroless" ]
        ARG RUN_IMAGE="gcr.io/distroless/java${RUNTIME_JRE_VERSION}-debian12:nonroot"
    ELSE IF PROC [ "${DISTRO}" = "alpine" ]
        ARG RUN_IMAGE="eclipse-temurin:${RUNTIME_JRE_VERSION}-jre-alpine"
    ELSE IF PROC [ "${DISTRO}" = "corretto" ]
        ARG RUN_IMAGE="amazoncorretto:${RUNTIME_JRE_VERSION}"
    ELSE IF PROC [ "${DISTRO}" = "liberica" ]
        ARG RUN_IMAGE="bellsoft/liberica-openjre-alpine:${RUNTIME_JRE_VERSION}"
    ELSE IF PROC [ "${DISTRO}" = "ubi" ]
        ARG RUN_IMAGE="registry.access.redhat.com/ubi9/openjdk-${RUNTIME_JRE_VERSION}-runtime:latest"
    ELSE
        ARG RUN_IMAGE="eclipse-temurin:${RUNTIME_JRE_VERSION}-jre"
    ENDIF
ENDFUNC

# ============================================================================
# FRAMEWORK DETECTION
# ============================================================================
FUNC detect_framework
    IF PROC --from=busybox:latest --mount=target=. grep -q "spring-boot-starter" pom.xml build.gradle build.gradle.kts 2>/dev/null
        ARG FRAMEWORK_TYPE="springboot"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "quarkus-universe-bom\|io.quarkus" pom.xml build.gradle build.gradle.kts 2>/dev/null
        ARG FRAMEWORK_TYPE="quarkus"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "micronaut-bom\|io.micronaut" pom.xml build.gradle build.gradle.kts 2>/dev/null
        ARG FRAMEWORK_TYPE="micronaut"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "jakarta.jakartaee-api\|javax.javaee-api" pom.xml build.gradle build.gradle.kts 2>/dev/null
        ARG FRAMEWORK_TYPE="jakartaee"
    ELSE
        ARG FRAMEWORK_TYPE="standard"
    ENDIF
ENDFUNC

# ============================================================================
# DISTRO DETECTION & IMAGE SELECTION
# ============================================================================
FUNC detect_distro
    # Detect if GraalVM native build is requested
    IF PROC --from=busybox:latest --mount=target=. grep -q "native-maven-plugin\|org.graalvm.buildtools" pom.xml build.gradle build.gradle.kts 2>/dev/null
        ARG BUILD_NATIVE=true
        ARG DISTRO="graalvm"
    ENDIF
    
    # Check for distro preference in properties
    IF PROC --from=busybox:latest --mount=target=. grep -q "base.image.*alpine" pom.xml gradle.properties 2>/dev/null
        ARG DISTRO="alpine"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "base.image.*distroless" pom.xml gradle.properties 2>/dev/null
        ARG DISTRO="distroless"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "base.image.*ubi" pom.xml gradle.properties 2>/dev/null
        ARG DISTRO="ubi"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "base.image.*corretto" pom.xml gradle.properties 2>/dev/null
        ARG DISTRO="corretto"
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q "base.image.*liberica" pom.xml gradle.properties 2>/dev/null
        ARG DISTRO="liberica"
    ENDIF
ENDFUNC

# ============================================================================
# MAVEN BUILD CONFIGURATION
# ============================================================================
FUNC maven
    # Extract Java version from pom.xml
    IF PROC --from=busybox:latest --mount=target=. SOURCE_VERSION=$(awk -F'[<>]' '/<maven.compiler.source>|<java.version>/{print $3; exit}' pom.xml 2>/dev/null) && [ -n "$SOURCE_VERSION" ] && echo "$SOURCE_VERSION"
        ARG RUNTIME_JRE_VERSION=${STDOUT}
    ENDIF
    
    # Set build image based on distro and GraalVM
    IF PROC [ "${BUILD_NATIVE}" = "true" ]
        ARG BUILD_IMAGE="ghcr.io/graalvm/native-image-community:${RUNTIME_JRE_VERSION}-ol9"
    ELSE IF PROC [ "${DISTRO}" = "alpine" ]
        ARG BUILD_IMAGE="maven:3.9-eclipse-temurin-${RUNTIME_JRE_VERSION}-alpine"
    ELSE IF PROC [ "${DISTRO}" = "corretto" ]
        ARG BUILD_IMAGE="maven:3.9-amazoncorretto-${RUNTIME_JRE_VERSION}"
    ELSE IF PROC [ "${DISTRO}" = "liberica" ]
        ARG BUILD_IMAGE="bellsoft/liberica-openjdk-alpine:${RUNTIME_JRE_VERSION}"
    ELSE IF PROC [ "${DISTRO}" = "ubi" ]
        ARG BUILD_IMAGE="registry.access.redhat.com/ubi9/openjdk-${RUNTIME_JRE_VERSION}:latest"
    ELSE
        ARG BUILD_IMAGE="maven:3.9-eclipse-temurin-${RUNTIME_JRE_VERSION}"
    ENDIF
    
    # Set runtime image
    FUNC CALL set_runtime_image
ENDFUNC

# ============================================================================
# GRADLE BUILD CONFIGURATION
# ============================================================================
FUNC gradle
    # Extract Java version from gradle.properties or build.gradle
    IF PROC --from=busybox:latest --mount=target=. VERSION=$(awk -F'=' '/^java.version=|^javaVersion=/{print $2}' gradle.properties 2>/dev/null | tr -d ' "'\''') && [ -n "$VERSION" ] && echo "$VERSION"
        ARG RUNTIME_JRE_VERSION=${STDOUT}
    ELSE IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP '(?<=sourceCompatibility\s=\s["'\'']?)[0-9.]+' build.gradle build.gradle.kts 2>/dev/null | head -1) && [ -n "$VERSION" ] && echo "$VERSION"
        ARG RUNTIME_JRE_VERSION=${STDOUT}
    ENDIF
    
    # Set build image based on distro and GraalVM
    IF PROC [ "${BUILD_NATIVE}" = "true" ]
        ARG BUILD_IMAGE="ghcr.io/graalvm/native-image-community:${RUNTIME_JRE_VERSION}-ol9"
    ELSE IF PROC [ "${DISTRO}" = "alpine" ]
        ARG BUILD_IMAGE="gradle:8-jdk${RUNTIME_JRE_VERSION}-alpine"
    ELSE IF PROC [ "${DISTRO}" = "corretto" ]
        ARG BUILD_IMAGE="gradle:8-jdk${RUNTIME_JRE_VERSION}-amazoncorretto"
    ELSE IF PROC [ "${DISTRO}" = "ubi" ]
        ARG BUILD_IMAGE="registry.access.redhat.com/ubi9/openjdk-${RUNTIME_JRE_VERSION}:latest"
    ELSE
        ARG BUILD_IMAGE="gradle:8-jdk${RUNTIME_JRE_VERSION}"
    ENDIF
    
    # Set runtime image
    FUNC CALL set_runtime_image
ENDFUNC

# ============================================================================
# ANT + IVY BUILD CONFIGURATION
# ============================================================================
FUNC ant
    # Extract Java version from build.xml
    IF PROC --from=busybox:latest --mount=target=. VERSION=$(awk -F'[" =]' '/<javac[^>]*source/{for(i=1;i<=NF;i++)if($i~/^[0-9.]+$/)print $i}' build.xml 2>/dev/null | head -1) && [ -n "$VERSION" ] && echo "$VERSION"
        ARG RUNTIME_JRE_VERSION=${STDOUT}
    ENDIF
    
    # Set build image
    IF PROC [ "${DISTRO}" = "alpine" ]
        ARG BUILD_IMAGE="eclipse-temurin:${RUNTIME_JRE_VERSION}-jdk-alpine"
    ELSE IF PROC [ "${DISTRO}" = "corretto" ]
        ARG BUILD_IMAGE="amazoncorretto:${RUNTIME_JRE_VERSION}"
    ELSE IF PROC [ "${DISTRO}" = "liberica" ]
        ARG BUILD_IMAGE="bellsoft/liberica-openjdk-alpine:${RUNTIME_JRE_VERSION}"
    ELSE IF PROC [ "${DISTRO}" = "ubi" ]
        ARG BUILD_IMAGE="registry.access.redhat.com/ubi9/openjdk-${RUNTIME_JRE_VERSION}:latest"
    ELSE
        ARG BUILD_IMAGE="eclipse-temurin:${RUNTIME_JRE_VERSION}-jdk"
    ENDIF
    
    # Set runtime image
    FUNC CALL set_runtime_image
ENDFUNC

# ============================================================================
# MAIN BUILD SYSTEM DETECTION
# ============================================================================
FUNC CALL detect_framework
FUNC CALL detect_distro

IF PROC --from=busybox:latest --mount=target=. [ -f "pom.xml" ]
    FUNC CALL maven
ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]
    FUNC CALL gradle
ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "build.xml" ]
    FUNC CALL ant
ELSE
    RUN echo "ERROR: No build file found (pom.xml, build.gradle, build.gradle.kts, or build.xml)" >&2 && exit 1
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
    set -e; \
    mkdir -p ./dexfile-artifact; \
    \
    if [ -f "mvnw" ]; then \
        if [ "${BUILD_NATIVE}" = "true" ]; then \
            ./mvnw ${MAVEN_CLI_OPTS} -Pnative package; \
            find target -type f -name "*-runner" -exec cp {} ./dexfile-artifact/app \; || \
            (echo "ERROR: GraalVM native build failed" >&2 && exit 1); \
        else \
            ./mvnw ${MAVEN_CLI_OPTS} clean package; \
            PACKAGING=$(awk -F'[<>]' '/<packaging>/{print $3; exit}' pom.xml 2>/dev/null || echo "jar"); \
            if [ "$PACKAGING" = "war" ]; then \
                find target -type f -name "*.war" -exec cp {} ./dexfile-artifact/app.war \; || \
                (echo "ERROR: WAR artifact not found" >&2 && exit 1); \
            else \
                find target -type f -name "*-runner.jar" -exec cp {} ./dexfile-artifact/app.jar \; 2>/dev/null || \
                find target -type f -name "*.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" -exec cp {} ./dexfile-artifact/app.jar \; || \
                (echo "ERROR: JAR artifact not found" >&2 && exit 1); \
            fi; \
        fi; \
    elif [ -f "gradlew" ]; then \
        if [ "${BUILD_NATIVE}" = "true" ]; then \
            ./gradlew ${GRADLE_OPTS} --no-daemon nativeCompile; \
            find build/native -type f -perm /u+x -exec cp {} ./dexfile-artifact/app \; || \
            (echo "ERROR: GraalVM native build failed" >&2 && exit 1); \
        else \
            ./gradlew ${GRADLE_OPTS} --no-daemon clean build -x test; \
            if grep -qE "id ['\"]war['\"]|apply plugin: ['\"]war['\"]" build.gradle* 2>/dev/null; then \
                find build/libs -type f -name "*.war" -exec cp {} ./dexfile-artifact/app.war \; || \
                (echo "ERROR: WAR artifact not found" >&2 && exit 1); \
            else \
                find build/libs -type f -name "*-runner.jar" -exec cp {} ./dexfile-artifact/app.jar \; 2>/dev/null || \
                find build/libs -type f -name "*.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" ! -name "*-plain.jar" -exec cp {} ./dexfile-artifact/app.jar \; || \
                (echo "ERROR: JAR artifact not found" >&2 && exit 1); \
            fi; \
        fi; \
    elif [ -f "pom.xml" ]; then \
        if [ "${BUILD_NATIVE}" = "true" ]; then \
            mvn ${MAVEN_CLI_OPTS} -Pnative package; \
            find target -type f -name "*-runner" -exec cp {} ./dexfile-artifact/app \; || \
            (echo "ERROR: GraalVM native build failed" >&2 && exit 1); \
        else \
            mvn ${MAVEN_CLI_OPTS} clean package; \
            PACKAGING=$(awk -F'[<>]' '/<packaging>/{print $3; exit}' pom.xml 2>/dev/null || echo "jar"); \
            if [ "$PACKAGING" = "war" ]; then \
                find target -type f -name "*.war" -exec cp {} ./dexfile-artifact/app.war \; || \
                (echo "ERROR: WAR artifact not found" >&2 && exit 1); \
            else \
                find target -type f -name "*.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" -exec cp {} ./dexfile-artifact/app.jar \; || \
                (echo "ERROR: JAR artifact not found" >&2 && exit 1); \
            fi; \
        fi; \
    elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then \
        gradle ${GRADLE_OPTS} --no-daemon clean build -x test; \
        if grep -qE "id ['\"]war['\"]|apply plugin: ['\"]war['\"]" build.gradle* 2>/dev/null; then \
            find build/libs -type f -name "*.war" -exec cp {} ./dexfile-artifact/app.war \; || \
            (echo "ERROR: WAR artifact not found" >&2 && exit 1); \
        else \
            find build/libs -type f -name "*.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" ! -name "*-plain.jar" -exec cp {} ./dexfile-artifact/app.jar \; || \
            (echo "ERROR: JAR artifact not found" >&2 && exit 1); \
        fi; \
    elif [ -f "build.xml" ]; then \
        ant clean 2>/dev/null || true; \
        ant jar 2>/dev/null || ant war 2>/dev/null || ant build 2>/dev/null || ant; \
        if grep -q '<war ' build.xml 2>/dev/null; then \
            find . -type f -name "*.war" \( -path "./dist/*" -o -path "./build/*" -o -path "./target/*" \) -exec cp {} ./dexfile-artifact/app.war \; || \
            (echo "ERROR: WAR artifact not found" >&2 && exit 1); \
        else \
            find . -type f -name "*.jar" \( -path "./dist/*" -o -path "./build/*" -o -path "./target/*" \) -exec cp {} ./dexfile-artifact/app.jar \; || \
            (echo "ERROR: JAR artifact not found" >&2 && exit 1); \
        fi; \
    else \
        echo "ERROR: No build configuration found" >&2 && exit 1; \
    fi

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