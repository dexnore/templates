#!/bin/sh
set -eu

############################################
# 1. Defaults & Meta
############################################
OUT="${GO_OUTPUT_BIN_PATH:-./dexfile-artifact}"
APP_NAME="${APP_NAME:-app}"
LIB_DIR_NAME="${LIB_DIR_NAME:-lib}"

APP_DIR="$OUT/$APP_NAME"
LIB_DIR="$APP_DIR/$LIB_DIR_NAME"
META_DIR="$OUT/meta"

SKIP_TESTS="${SKIP_TESTS:-true}"
BUILD_NATIVE="${BUILD_NATIVE:-false}"
LOG_LEVEL="${LOG_LEVEL:-info}"
JAVA_CMD="${JAVA_CMD:-java}"

mkdir -p "$APP_DIR" "$LIB_DIR" "$META_DIR"

log()  { [ "$LOG_LEVEL" != error ] && printf "[INFO] %s\n" "$*" >&2; }
dbg()  { [ "$LOG_LEVEL" = debug ] && printf "[DEBUG] %s\n" "$*" >&2; }
warn() { printf "[WARN] %s\n" "$*" >&2; }
err()  { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

############################################
# 2. Utility (BusyBox-safe)
############################################
pick_largest() {
  _dir="$1"
  _ext="${2:-}"
  find "$_dir" -type f 2>/dev/null \
    ${_ext:+-name "*.$_ext"} \
    ! -name "*-sources*.jar" \
    ! -name "*-javadoc*.jar" \
    ! -name "*-plain*.jar" \
    ! -name "*-original*.jar" |
  while IFS= read -r f; do
    size=$(wc -c <"$f" 2>/dev/null || echo 0)
    printf "%s\t%s\n" "$size" "$f"
  done |
  sort -nr | head -n 1 | cut -f2
}

is_executable() {
  [ -x "$1" ] || return 1
  file "$1" 2>/dev/null | grep -qE "(ELF|Mach-O|executable)"
}

get_main_class() {
  unzip -p "$1" META-INF/MANIFEST.MF 2>/dev/null |
    tr -d '\r\n' | sed -n 's/^Main-Class:[[:space:]]*//p' | head -n 1
}

has_spring_boot_loader() {
  unzip -l "$1" 2>/dev/null | grep -q "org/springframework/boot/loader"
}

############################################
# 3. Build System Detection
############################################
BT=""
[ -f "./mvnw" ] && BT="./mvnw" || [ -f "pom.xml" ] && BT="mvn" || \
[ -f "./gradlew" ] && BT="./gradlew" || [ -f "build.gradle" ] && BT="gradle" || \
[ -f "build.xml" ] && BT="ant" || err "No build system detected"

log "Build system: $BT"
[ "$BT" = "./mvnw" ] && chmod +x "$BT"
[ "$BT" = "./gradlew" ] && chmod +x "$BT"

############################################
# 4. Hooks
############################################
[ -n "${PRE_BUILD_HOOK:-}" ] && eval "$PRE_BUILD_HOOK"

############################################
# 5. Build Execution
############################################
case "$BT" in
  ./mvnw|mvn)
    CMD="$BT"
    if [ "$BUILD_NATIVE" = true ]; then
      $CMD clean package -Pnative -DskipTests="$SKIP_TESTS" -B
      BIN="$(pick_largest target)"
      is_executable "$BIN" || err "Native binary not found"
      cp "$BIN" "$APP_DIR/app"
      echo native > "$META_DIR/type" && exit 0
    fi
    $CMD clean package -DskipTests="$SKIP_TESTS" -B
    ;;
  ./gradlew|gradle)
    CMD="$BT"
    if [ "$BUILD_NATIVE" = true ]; then
      $CMD --no-daemon nativeCompile
      BIN="$(pick_largest build/native || pick_largest target)"
      is_executable "$BIN" || err "Native binary not found"
      cp "$BIN" "$APP_DIR/app"
      echo native > "$META_DIR/type" && exit 0
    fi
    $CMD --no-daemon clean build -x test
    ;;
  ant)
    ant clean jar war build || ant
    ;;
esac

[ -n "${POST_BUILD_HOOK:-}" ] && eval "$POST_BUILD_HOOK"

############################################
# 6. Artifact Resolution & Multi-module Main-Class Detection
############################################
# Pick largest artifact by default
ARTIFACT="${FORCE_ARTIFACT:-$(pick_largest .)}"
[ -f "$ARTIFACT" ] || err "No build artifact found"

# Detect Main-Class recursively across modules
detect_main_class() {
  [ -n "${FORCE_MAIN_CLASS:-}" ] && { echo "$FORCE_MAIN_CLASS"; return; }

  # 1. Check top-level artifact
  MC="$(get_main_class "$ARTIFACT")"
  [ -n "$MC" ] && { echo "$MC"; return; }

  # 2. Search all module jars
  while IFS= read -r J; do
    MC="$(get_main_class "$J")"
    [ -n "$MC" ] && { echo "$MC"; return; }
  done <<EOF
$(find . -type f -name "*.jar" ! -name "$(basename "$ARTIFACT")" 2>/dev/null)
EOF
}

MAIN_CLASS="$(detect_main_class)"

case "$ARTIFACT" in
  *.war)
    log "WAR detected: $(basename "$ARTIFACT")"
    cp "$ARTIFACT" "$APP_DIR/app.war"
    echo war > "$META_DIR/type"
    ;;
  *.jar)
    if has_spring_boot_loader "$ARTIFACT" || [ -n "$MAIN_CLASS" ]; then
      log "Executable JAR detected"
      cp "$ARTIFACT" "$APP_DIR/app.jar"
      echo jar > "$META_DIR/type"
      [ -n "$MAIN_CLASS" ] && echo "$MAIN_CLASS" > "$META_DIR/main_class"
    else
      log "Thin JAR detected — aggregating all module dependencies"

      cp "$ARTIFACT" "$APP_DIR/app.jar"

      DEP_DIRS="target/lib build/libs/lib target/dependency build/install/*/lib"
      for d in $DEP_DIRS; do
        [ -d "$d" ] && cp -L "$d"/*.jar "$LIB_DIR/" 2>/dev/null || true
      done

      # Include other module JAR outputs
      while IFS= read -r J; do
        cp -L "$J" "$LIB_DIR/" 2>/dev/null || true
      done <<EOF
$(find . -type f -name "*.jar" ! -name "$(basename "$ARTIFACT")" 2>/dev/null)
EOF

      [ -z "$MAIN_CLASS" ] && err "Main-Class not found. Set FORCE_MAIN_CLASS."
      echo classpath > "$META_DIR/type"
      echo "$MAIN_CLASS" > "$META_DIR/main_class"
    fi
    ;;
esac

############################################
# 7. Runtime Launcher
############################################
cat > "$APP_DIR/run.sh" <<EOF
#!/bin/sh
BASE="\$(cd "\$(dirname "\$0")" && pwd)"
cd "\$BASE"
M_CLASS="\$(cat ../meta/main_class 2>/dev/null || echo "\${FORCE_MAIN_CLASS:-}")"
exec $JAVA_CMD \$JAVA_OPTS -cp "app.jar:$LIB_DIR_NAME/*" "\$M_CLASS" "\$@"
EOF

chmod +x "$APP_DIR/run.sh"
log "Artifact staged: $OUT/ (Type: $(cat "$META_DIR/type"))"
