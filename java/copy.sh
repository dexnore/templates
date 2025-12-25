#!/bin/sh
# =============================================================================
# ULTIMATE JAVA ARTIFACT RESOLVER — FINAL ENTERPRISE EDITION
# Output: Dockerfile COPY instructions + ENTRYPOINT_ARTIFACT
# =============================================================================
set -eu

###############################################################################
# CONFIG
###############################################################################
OUT_ROOT="${JAVA_LAYOUT_ROOT:-/opt/app}"
APP_DIR="$OUT_ROOT/app"
LIB_DIR="$APP_DIR/lib"
ROOTS=". target build dist out"

ARTIFACT_PATH="${ARTIFACT_PATH:-}"
LIBS_PATH="${LIBS_PATH:-}"

###############################################################################
# LOGGING
###############################################################################
if [ -t 2 ]; then
  I="\033[1;34m[INFO]\033[0m"
  E="\033[1;31m[ERROR]\033[0m"
else
  I="[INFO]"
  E="[ERROR]"
fi

log(){ printf "%s %s\n" "$I" "$*" >&2; }
die(){ printf "%s %s\n" "$E" "$*" >&2; exit 1; }

###############################################################################
# SAFE HELPERS (NO FALSE POSITIVES)
###############################################################################
is_elf()        { file "$1" 2>/dev/null | grep -qi '^ELF .* executable'; }
is_zip_ok()     { unzip -t "$1" >/dev/null 2>&1; }

has_main() {
  unzip -p "$1" META-INF/MANIFEST.MF 2>/dev/null |
    grep -qi '^Main-Class:'
}

is_boot() {
  unzip -l "$1" 2>/dev/null |
    grep -qE 'BOOT-INF/|org/springframework/boot/loader'
}

is_quarkus_runner() {
  unzip -l "$1" 2>/dev/null | grep -q 'io/quarkus/runtime'
}

is_tooling() {
  echo "$1" | grep -qiE '(maven-|gradle-|plugin-|annotation-|processor)'
}

is_test_artifact() {
  echo "$1" | grep -qiE '(test|junit|mockito)'
}

size() {
  stat -c %s "$1" 2>/dev/null || ls -ln "$1" | awk '{print $5}'
}

###############################################################################
# OUTPUT EMITTERS (STRICT)
###############################################################################
emit_file() {
  printf 'COPY --from=builder %s %s/%s\n' "$1" "$APP_DIR" "$2"
}

emit_dir() {
  printf 'COPY --from=builder %s/ %s/\n' "$1" "$2"
}

emit_entry() {
  printf 'ENTRYPOINT_ARTIFACT=%s\n' "$1"
}

###############################################################################
# 1. USER OVERRIDE (ABSOLUTE AUTHORITY)
###############################################################################
if [ -n "$ARTIFACT_PATH" ]; then
  [ -e "$ARTIFACT_PATH" ] || die "ARTIFACT_PATH does not exist"

  log "User override: $ARTIFACT_PATH"

  if [ -d "$ARTIFACT_PATH" ]; then
    emit_dir "$ARTIFACT_PATH" "$APP_DIR"
    emit_entry "$APP_DIR"
  else
    name="$(basename "$ARTIFACT_PATH")"
    emit_file "$ARTIFACT_PATH" "$name"
    emit_entry "$APP_DIR/$name"
  fi

  [ -n "$LIBS_PATH" ] && [ -d "$LIBS_PATH" ] && emit_dir "$LIBS_PATH" "$LIB_DIR"
  exit 0
fi

###############################################################################
# 2. NATIVE IMAGE (STRICT ELF)
###############################################################################
for r in $ROOTS; do
  [ -d "$r" ] || continue
  find "$r" -type f -perm -111 2>/dev/null |
  while read -r f; do
    is_elf "$f" || continue
    echo "$f"
    break
  done
done | head -n1 | while read -r bin; do
  log "Native executable detected: $bin"
  emit_file "$bin" run.bin
  emit_entry "$APP_DIR/run.bin"
  exit 0
done

###############################################################################
# 3. QUARKUS FAST-JAR (IMMUTABLE)
###############################################################################
for r in $ROOTS; do
  if [ -f "$r/quarkus-app/quarkus-run.jar" ]; then
    log "Quarkus fast-jar detected"
    emit_dir "$r/quarkus-app" "$APP_DIR"
    emit_entry "$APP_DIR/quarkus-run.jar"
    exit 0
  fi
done

###############################################################################
# 4. ARTIFACT SCORING ENGINE
###############################################################################
log "Scanning JVM artifacts..."

BEST="$(
for r in $ROOTS; do
  [ -d "$r" ] || continue
  find "$r" -type f \( -name '*.jar' -o -name '*.war' \) 2>/dev/null |
  while read -r a; do
    is_tooling "$a" && continue
    is_test_artifact "$a" && continue
    is_zip_ok "$a" || continue

    tier=1
    is_boot "$a" && tier=6
    is_quarkus_runner "$a" && tier=5
    has_main "$a" && tier=4
    [ "${a##*.}" = war ] && tier=3

    sz=$(printf "%012d" "$(size "$a")")
    printf "%02d-%s %s\n" "$tier" "$sz" "$a"
  done
done | sort -r | head -n1 | awk '{print $2}'
)"

###############################################################################
# 5. FALLBACK: EXPLODED APP
###############################################################################
if [ -z "$BEST" ]; then
  for r in $ROOTS; do
    for d in "$r/classes" "$r/app" "$r/exploded"; do
      [ -d "$d" ] || continue
      log "Exploded JVM app detected: $d"
      emit_dir "$d" "$APP_DIR"
      emit_entry "$APP_DIR"
      exit 0
    done
  done
  die "No runnable Java artifact found"
fi

###############################################################################
# 6. LIBRARY DISCOVERY (THIN JARS)
###############################################################################
for d in $(
  find . -type d \( -name lib -o -name libs -o -name dependency \) 2>/dev/null |
  while read -r l; do
    ls "$l"/*.jar >/dev/null 2>&1 && echo "$l"
  done | sort -u
); do
  log "Including libs: $d"
  emit_dir "$d" "$LIB_DIR"
done

###############################################################################
# 7. FINAL EMISSION
###############################################################################
name="$(basename "$BEST")"
log "Selected artifact: $BEST"

emit_file "$BEST" "$name"
emit_entry "$APP_DIR/$name"
