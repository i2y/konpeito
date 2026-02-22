#!/bin/bash
# Build the Konpeito ASM tool
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JAVA="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}/bin/javac"
JAR_CMD="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}/bin/jar"
ASM_JAR="$SCRIPT_DIR/lib/asm-9.7.1.jar"
BUILD_DIR="$SCRIPT_DIR/build"
OUT_JAR="$SCRIPT_DIR/konpeito-asm.jar"

# Use javac/jar from PATH if JAVA_HOME not set and homebrew path doesn't exist
if [ ! -f "$JAVA" ]; then
    JAVA="javac"
    JAR_CMD="jar"
fi

echo "Building konpeito-asm tool..."

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/com/konpeito/asm"
mkdir -p "$BUILD_DIR/konpeito/runtime"

# Compile ASM tool and runtime classes
"$JAVA" -cp "$ASM_JAR" \
    -Xlint:none \
    -nowarn \
    -d "$BUILD_DIR" \
    "$SCRIPT_DIR/src/KonpeitoAssembler.java" \
    "$SCRIPT_DIR/src/ClassIntrospector.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KArray.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KHash.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KThread.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KConditionVariable.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KSizedQueue.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KJSON.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KCrypto.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KCompression.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KHTTP.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KTime.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KFile.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KMath.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KRactor.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KRactorPort.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KMatchData.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/KFiber.java" \
    "$SCRIPT_DIR/src/konpeito/runtime/RubyDispatch.java"

# Copy runtime classes to a separate directory for JAR bundling
RUNTIME_DIR="$SCRIPT_DIR/runtime-classes"
rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR/konpeito/runtime"
cp "$BUILD_DIR/konpeito/runtime/"*.class "$RUNTIME_DIR/konpeito/runtime/"

# Create manifest
echo "Main-Class: com.konpeito.asm.KonpeitoAssembler" > "$BUILD_DIR/MANIFEST.MF"

# Extract ASM classes into build dir (to create a fat jar)
cd "$BUILD_DIR"
"$JAR_CMD" xf "$ASM_JAR"
rm -rf META-INF/MANIFEST.MF 2>/dev/null || true

# Create fat jar
"$JAR_CMD" cfm "$OUT_JAR" "$BUILD_DIR/MANIFEST.MF" -C "$BUILD_DIR" .

echo "Built: $OUT_JAR"
