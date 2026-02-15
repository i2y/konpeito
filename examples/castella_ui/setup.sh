#!/bin/bash
# Setup script: downloads JWM + Skija JARs and compiles KUIRuntime.java
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Find Java tools
case "$(uname -s)" in
  Darwin*) DEFAULT_JAVA_HOME="/opt/homebrew/opt/openjdk@21" ;;
  MINGW*|MSYS*|CYGWIN*) DEFAULT_JAVA_HOME="C:/Program Files/Java/jdk-21" ;;
  *) DEFAULT_JAVA_HOME="/usr/lib/jvm/java-21-openjdk" ;;
esac

JAVA_HOME="${JAVA_HOME:-$DEFAULT_JAVA_HOME}"
if [ -x "$JAVA_HOME/bin/javac" ]; then
  JAVAC="$JAVA_HOME/bin/javac"
elif command -v javac &>/dev/null; then
  JAVAC="javac"
else
  echo "Error: javac not found. Install Java 21+."
  exit 1
fi

LIBS_DIR="$SCRIPT_DIR/lib"
CLASSES_DIR="$SCRIPT_DIR/classes"
mkdir -p "$LIBS_DIR" "$CLASSES_DIR"

# Platform detection
OS="$(uname -s)"
ARCH="$(uname -m)"

JWM_VERSION="0.4.8"
SKIJA_VERSION="0.116.2"
SKIJA_SHARED_VERSION="0.116.2"
TYPES_VERSION="0.2.0"

MAVEN_BASE="https://repo1.maven.org/maven2/io/github/humbleui"

# Download JWM
if [ ! -f "$LIBS_DIR/jwm.jar" ]; then
  echo "Downloading JWM ${JWM_VERSION}..."
  curl -sL -o "$LIBS_DIR/jwm.jar" \
    "${MAVEN_BASE}/jwm/${JWM_VERSION}/jwm-${JWM_VERSION}.jar"
else
  echo "JWM already downloaded."
fi

# Download Skija shared (Java classes: Canvas, Paint, Surface, etc.)
if [ ! -f "$LIBS_DIR/skija-shared.jar" ]; then
  echo "Downloading Skija shared ${SKIJA_SHARED_VERSION}..."
  curl -sL -o "$LIBS_DIR/skija-shared.jar" \
    "${MAVEN_BASE}/skija-shared/${SKIJA_SHARED_VERSION}/skija-shared-${SKIJA_SHARED_VERSION}.jar"
else
  echo "Skija shared already downloaded."
fi

# Download platform-specific Skija (native libraries: .dylib/.so/.dll)
case "$OS-$ARCH" in
  Darwin-arm64)  SKIJA_PLATFORM="macos-arm64" ;;
  Darwin-x86_64) SKIJA_PLATFORM="macos-x64"   ;;
  Linux-x86_64)  SKIJA_PLATFORM="linux-x64"   ;;
  Linux-aarch64) SKIJA_PLATFORM="linux-arm64"  ;;
  MINGW*-x86_64|MSYS*-x86_64|CYGWIN*-x86_64) SKIJA_PLATFORM="windows-x64" ;;
  *)             echo "Unsupported platform: $OS-$ARCH"; exit 1 ;;
esac

if [ ! -f "$LIBS_DIR/skija-platform.jar" ]; then
  echo "Downloading Skija (${SKIJA_PLATFORM}) ${SKIJA_VERSION}..."
  curl -sL -o "$LIBS_DIR/skija-platform.jar" \
    "${MAVEN_BASE}/skija-${SKIJA_PLATFORM}/${SKIJA_VERSION}/skija-${SKIJA_PLATFORM}-${SKIJA_VERSION}.jar"
else
  echo "Skija platform already downloaded."
fi

# Download HumbleUI Types
if [ ! -f "$LIBS_DIR/types.jar" ]; then
  echo "Downloading Types ${TYPES_VERSION}..."
  curl -sL -o "$LIBS_DIR/types.jar" \
    "${MAVEN_BASE}/types/${TYPES_VERSION}/types-${TYPES_VERSION}.jar"
else
  echo "Types already downloaded."
fi

# Determine classpath separator
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) CP_SEP=";" ;;
  *) CP_SEP=":" ;;
esac

# Compile KUIRuntime.java
echo "Compiling KUIRuntime..."
"$JAVAC" -cp "${LIBS_DIR}/jwm.jar${CP_SEP}${LIBS_DIR}/skija-shared.jar${CP_SEP}${LIBS_DIR}/skija-platform.jar${CP_SEP}${LIBS_DIR}/types.jar" \
  -d "$CLASSES_DIR" \
  "$SCRIPT_DIR/src/konpeito/ui/KUIRuntime.java"

echo ""
echo "Setup complete!"
echo "  JARs:    $LIBS_DIR/"
echo "  Classes: $CLASSES_DIR/"
echo ""
echo "Run the demo: bash run.sh"
