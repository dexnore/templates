# ============================================================================
# Resolve BUILD-TIME JDK image (fully user-customizable)
#
# ENV VARS / META ARGS:
#   DISTRO        - temurin | alpine | corretto | liberica | ubi | graalvm
#   JAVA_VERSION  - major or full (8,11,17,21,22,23,24,...)
#   BUILD_NATIVE  - true | false
#   DISTRO_VARIANT- optional, e.g., al2023, ubi8, ubi9
#
# STDOUT: full OCI image reference
# ============================================================================
resolve_build_jdk_image() {
    distro="${DISTRO:-temurin}"
    java="${JAVA_VERSION:-17}"
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
