#!/bin/bash
# Build and run the Castella UI demo
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ASM_DIR="$PROJECT_ROOT/tools/konpeito-asm"
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}"
JAVAC="$JAVA_HOME/bin/javac"
JAR="$JAVA_HOME/bin/jar"

# Check that setup has been run
if [ ! -d "$SCRIPT_DIR/lib" ] || [ ! -d "$SCRIPT_DIR/classes" ]; then
  echo "Please run setup.sh first:"
  echo "  cd examples/castella_ui && bash setup.sh"
  exit 1
fi

# --- Auto-rebuild Java sources if changed ---

# 1) KUIRuntime.java → classes/
KUI_SRC="$SCRIPT_DIR/src/konpeito/ui/KUIRuntime.java"
KUI_CLS="$SCRIPT_DIR/classes/konpeito/ui/KUIRuntime.class"
if [ "$KUI_SRC" -nt "$KUI_CLS" ] 2>/dev/null; then
  echo "[run.sh] Recompiling KUIRuntime.java..."
  "$JAVAC" -cp "$SCRIPT_DIR/lib/jwm.jar:$SCRIPT_DIR/lib/skija-shared.jar:$SCRIPT_DIR/lib/types.jar" \
    -d "$SCRIPT_DIR/classes" "$KUI_SRC"
fi

# 2) Runtime classes (RubyDispatch, KArray, etc.) → runtime-classes/
RUNTIME_SRC_DIR="$ASM_DIR/src/konpeito/runtime"
RUNTIME_OUT_DIR="$ASM_DIR/runtime-classes/konpeito/runtime"
NEED_RUNTIME_REBUILD=false
for src in "$RUNTIME_SRC_DIR"/*.java; do
  [ -f "$src" ] || continue
  base="$(basename "$src" .java)"
  cls="$RUNTIME_OUT_DIR/$base.class"
  if [ "$src" -nt "$cls" ] 2>/dev/null; then
    NEED_RUNTIME_REBUILD=true
    break
  fi
done
if $NEED_RUNTIME_REBUILD; then
  echo "[run.sh] Recompiling runtime classes..."
  "$JAVAC" -d "$ASM_DIR/runtime-classes" "$RUNTIME_SRC_DIR"/*.java
  # Also update classes/ for direct use
  cp "$RUNTIME_OUT_DIR"/*.class "$SCRIPT_DIR/classes/konpeito/runtime/" 2>/dev/null || true
fi

# 3) KonpeitoAssembler.java → konpeito-asm.jar (fat jar)
ASM_SRC="$ASM_DIR/src/KonpeitoAssembler.java"
ASM_JAR="$ASM_DIR/konpeito-asm.jar"
if [ "$ASM_SRC" -nt "$ASM_JAR" ] 2>/dev/null; then
  echo "[run.sh] Recompiling konpeito-asm.jar..."
  "$JAVAC" -cp "$ASM_DIR/lib/asm-9.7.1.jar" \
    -d "$ASM_DIR/out" "$ASM_SRC" "$ASM_DIR/src/ClassIntrospector.java"
  # Build fat jar (ASM lib + compiled classes)
  TMP_FAT="$(mktemp -d)"
  (cd "$TMP_FAT" && "$JAR" xf "$ASM_DIR/lib/asm-9.7.1.jar" && cp -r "$ASM_DIR/out/com" .)
  "$JAR" cfe "$ASM_JAR" com.konpeito.asm.KonpeitoAssembler -C "$TMP_FAT" .
  rm -rf "$TMP_FAT"
fi

# --- Build and run ---

DEMO="${1:-hello.rb}"

CP="$SCRIPT_DIR/lib/jwm.jar:$SCRIPT_DIR/lib/skija-shared.jar:$SCRIPT_DIR/lib/skija-platform.jar:$SCRIPT_DIR/lib/types.jar:$SCRIPT_DIR/classes"

cd "$PROJECT_ROOT"

# Collect all RBS type definition files from the UI framework
RBS_OPTS=""
for rbs_file in "$PROJECT_ROOT"/lib/konpeito/ui/types/*.rbs; do
  [ -f "$rbs_file" ] && RBS_OPTS="$RBS_OPTS --rbs $rbs_file"
done

bundle exec ruby -Ilib bin/konpeito build --target jvm \
  --classpath "$CP" \
  $RBS_OPTS \
  --run \
  -o "$SCRIPT_DIR/demo.jar" \
  "$SCRIPT_DIR/$DEMO"
