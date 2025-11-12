# syntax=dexnore/dexfile:0

# This Dockerfile uses Dexfile syntax. For more information, see:
# https://github.com/dexnore/dexfile

ARG MAVEN_CLI_OPTS="-B -DskipTests"
ARG PORT=3000
ARG BUILD_IMAGE RUN_IMAGE RUNTIME_JRE_VERSION=17
WORKDIR /home/dexfile/app
FUNC maven
    ARG BUILD_IMAGE=maven:3.9-eclipse-temurin-${RUNTIME_JRE_VERSION}
    IF PROC [ -z "${BUILD_IMAGE}" ]
        IF PROC set -euo pipefail && SOURCE_VERSION=$(awk -F'[<>]' '/maven.compiler.source/{print $3}' pom.xml) && [ -n "$SOURCE_VERSION" ] && echo ${SOURCE_VERSION:-${RUNTIME_JRE_VERSION}}
            ARG BUILD_IMAGE="maven:3.9-eclipse-temurin-${STDOUT}"
            ARG RUNTIME_JRE_VERSION=${STDOUT}
        ENDIF
    ENDIF

    ARG RUN_IMAGE=eclipse-temurin:${RUNTIME_JRE_VERSION}-jre
    IF PROC [ -z "${RUN_IMAGE}" ]
        IF PROC TARGET_VERSION=$(awk -F'[<>]' '/maven.compiler.target/{print $3}' pom.xml) && echo ${TARGET_VERSION:-${RUNTIME_JRE_VERSION}}
            ARG RUNTIME_JRE_VERSION=${STDOUT}
            ARG RUN_IMAGE="eclipse-temurin:${STDOUT}-jre"
        ENDIF
    ENDIF
ENDFUNC

FUNC gradle
    ARG BUILD_IMAGE=maven:3.9-eclipse-temurin-${RUNTIME_JRE_VERSION}
    IF PROC [ -z "${BUILD_IMAGE}" ]
        IF PROC VERSION=$(awk -F'=' '/^java.version=/{print $2}' gradle.properties 2>/dev/null) && echo ${VERSION:-${RUNTIME_JRE_VERSION}}
            ARG BUILD_IMAGE="gradle:8-jdk${STDOUT}"
            ARG RUNTIME_JRE_VERSION=${STDOUT}
        ELSE IF PROC TARGET_VERSION=$(awk -F'[<>]' '/sourceCompatibility/{print $3}' build.gradle) && echo ${TARGET_VERSION:-${RUNTIME_JRE_VERSION}}
            ARG BUILD_IMAGE="gradle:8-jdk${STDOUT}"
            ARG RUNTIME_JRE_VERSION=${STDOUT}
        ENDIF
    ENDIF

    ARG RUN_IMAGE=eclipse-temurin:${RUNTIME_JRE_VERSION}-jre
    IF PROC [ -z "${RUN_IMAGE}" ]
        IF PROC TARGET_VERSION=$(awk -F'[<>]' '/targetCompatibility/{print $3}' build.gradle) && echo ${TARGET_VERSION:-${RUNTIME_JRE_VERSION}}}
            ARG RUN_IMAGE="eclipse-temurin:${STDOUT}-jre"
            ARG RUNTIME_JRE_VERSION=${STDOUT}
        ENDIF
    ENDIF
ENDFUNC

FUNC ant
    ARG BUILD_IMAGE=maven:3.9-eclipse-temurin-${RUNTIME_JRE_VERSION}
    IF PROC [ -z "${BUILD_IMAGE}" ]
        IF PROC TARGET_VERSION=$(awk -F'[<>]' '/<javac[^>]*source=/{gsub(/"/,"",$2); print $2}' build.xml) && echo ${TARGET_VERSION:-${RUNTIME_JRE_VERSION}}
            ARG BUILD_IMAGE="eclipse-temurin:${STDOUT}"
            ARG RUNTIME_JRE_VERSION=${STDOUT}
        ENDIF
    ENDIF

    ARG RUN_IMAGE=eclipse-temurin:${RUNTIME_JRE_VERSION}-jre
    IF PROC [ -z "${RUN_IMAGE}" ]
        IF PROC TARGET_VERSION=$(awk -F'[<>]' '/<javac[^>]*target=/{gsub(/"/,"",$2); print $2}' build.xml) && echo ${TARGET_VERSION:-${RUNTIME_JRE_VERSION}}
            ARG RUN_IMAGE="eclipse-temurin:${STDOUT}-jre"
            ARG RUNTIME_JRE_VERSION=${STDOUT}
        ENDIF
    ENDIF
ENDFUNC

IF PROC --from=busybox:latest --mount=target=. [ -f "pom.xml" ]
    FUNC CALL maven
ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "build.gradle" ]
    FUNC CALL gradle
ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "build.xml" ]
    FUNC CALL ant
ELSE
    RUN echo "no 'pom.xml', 'build.gradle' or 'build.xml' file found!" >&2 && exit 1;
ENDIF

IF PROC --from=busybox:latest --mount=target=. (PACKAGING=$(awk -F'[<>]' '/<packaging>/{print $3}' pom.xml) && [ "$PACKAGING" = "war" ]) || \
    (grep -q "id 'war'" build.gradle 2>/dev/null) || (grep -q "id 'war'" build.gradle.kts 2>/dev/null) || \
    (grep -q '<war ' build.xml 2>/dev/null)
    ARG RUN_IMAGE="tomcat:10-jre17-temurin"
    IF PROC --from=busybox:latest [ ! -z "${RUNTIME_JRE_VERSION}" ]
        ARG RUN_IMAGE="tomcat:10-jre${RUNTIME_JRE_VERSION}-temurin"
    ENDIF
ENDIF

FROM ${BUILD_IMAGE} AS base
WORKDIR /home/dexfile/app
ENV MAVEN_OPTS="-Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
ENV JAVA_OPTS="-Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
ENV MAVEN_CONFIG="/home/dexfile/.m2"

FROM base AS deps
COPY pom.xml* settings.xml* build.gradle* \
    build.gradle.kts* settings.gradle* \
    settings.gradle.kts* gradle.properties* \
    build.xml* mvnw* gradlew* \
    /home/dexfile/app/
RUN if [ -f "gradlew" ]; then chmod +x gradlew; \
    elif [ -f "mvnw" ]; then chmod +x mvnw; fi
RUN --mount=type=secret,id=m2settings,target=settings.xml \
    --mount=type=cache,target=~/.m2 \
    --mount=type=cache,target=~/.gradle \
    --mount=type=cache,target=/root/.ivy2 \
    if [ -f "mvnw" ]; then ./mvnw $MAVEN_CLI_OPTS dependency:go-offline; \
    elif [ -f "gradlew" ]; then ./gradlew --no-daemon dependencies || true; \
    elif [ -f "pom.xml" ]; then mvn $MAVEN_CLI_OPTS dependency:go-offline; \
    elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then \
        gradle --no-daemon dependencies || true; \
    elif [ -f "build.xml" ]; then ant -version || true; \
    else echo "failed to install dependencies: no build system detected" exit 1; fi

FROM base AS builder
COPY --from=deps . .
RUN --mount=type=secret,id=m2settings,target=settings.xml \
    --mount=type=cache,target=~/.m2 \
    --mount=type=cache,target=~/.gradle \
    --mount=type=cache,target=/root/.ivy2 \
    if [ -f "mvnw" ]; then \
        ./mvnw $MAVEN_CLI_OPTS clean package; \
        if PACKAGING=$(awk -F'[<>]' '/<packaging>/{print $3}' pom.xml) && [ "$PACKAGING" = "war" ]; then \
            mkdir -p ./dexfile-artifact && cp target/*.war ./dexfile-artifact/app.war || true; \
        else mkdir -p ./dexfile-artifact && cp target/*.jar ./dexfile-artifact/app.jar || true; fi; \
    elif [ -f "gradlew" ]; then \
        ./gradlew --no-daemon clean build; \
        if grep -q "id 'war'" build.gradle 2>/dev/null || grep -q "id 'war'" build.gradle.kts 2>/dev/null; then \
            mkdir -p ./dexfile-artifact && cp build/libs/*.war ./dexfile-artifact/app.war || true; \
        else mkdir -p ./dexfile-artifact && cp build/libs/*.jar ./dexfile-artifact/app.jar || true; fi; \
    elif [ -f "pom.xml" ]; then \
        mvn $MAVEN_CLI_OPTS clean package; \
        if PACKAGING=$(awk -F'[<>]' '/<packaging>/{print $3}' pom.xml) && [ "$PACKAGING" = "war" ]; then \
            mkdir -p ./dexfile-artifact && cp target/*.war ./dexfile-artifact/app.war || true; \
        else mkdir -p ./dexfile-artifact && cp target/*.jar ./dexfile-artifact/app.jar || true; fi; \
    elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then \
        gradle --no-daemon clean build; \
        if grep -q "id 'war'" build.gradle 2>/dev/null || grep -q "id 'war'" build.gradle.kts 2>/dev/null; then \
            mkdir -p ./dexfile-artifact && cp build/libs/*.war ./dexfile-artifact/app.war || true; \
        else mkdir -p ./dexfile-artifact && cp build/libs/*.jar ./dexfile-artifact/app.jar || true; fi; \
    elif [ -f "build.xml" ]; then \
        ant -Dskip.tests=true; \
        if grep -q '<war ' build.xml 2>/dev/null; then \
            mkdir -p ./dexfile-artifact && cp dist/*.war ./dexfile-artifact/app.war || cp build/*.war ./dexfile-artifact/app.war || true; \
        else mkdir -p ./dexfile-artifact && cp dist/*.jar ./dexfile-artifact/app.jar || cp build/*.jar ./dexfile-artifact/app.jar || true; fi; \
    else echo "no 'pom.xml', 'build.gradle' or 'build.xml' file found while building!" >&2 && exit 1; fi;

FROM ${RUN_IMAGE} AS app
RUN addgroup dexnore && adduser --ingroup dexnore dexfile --disabled-password
WORKDIR /home/dexfile/app
USER dexfile:dexnore
ENV JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:ActiveProcessorCount=2 -XX:MaxRAMPercentage=75.0"
ENV PORT=${PORT}
EXPOSE ${PORT}

FROM app AS prod
IF PROC --from=builder --mount=target=. [ -f "/home/dexfile/app/dexfile-artifact/app.war" ]
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dexfile-artifact/app.war /usr/local/tomcat/webapps/ROOT.war
    HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD curl -f http://127.0.0.1:${PORT}/ || exit 1
    ENTRYPOINT [ "catalina.sh", "run" ]
ELSE
    COPY --chown=dexfile:dexnore --from=builder /home/dexfile/app/dexfile-artifact/app.jar /home/dexfile/app/dexfile-artifact/app.jar
    ENTRYPOINT [ "java", "$JAVA_TOOL_OPTIONS", "-jar", "/home/dexfile/app/dexfile-artifact/app.jar" ]
ENDIF

FROM prod AS release
LABEL maintainer="@dexnore/dexfile"
LABEL moby.buildkit.frontend.network.none="true"
LABEL moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"

FROM release
