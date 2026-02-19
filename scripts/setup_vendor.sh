#!/bin/bash
# Setup vendored dependencies for Konpeito
#
# Downloads yyjson (fast JSON library) source files.
# Run this after cloning the repository:
#   bash scripts/setup_vendor.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
YYJSON_DIR="$PROJECT_ROOT/vendor/yyjson"

YYJSON_VERSION="0.10.0"
YYJSON_BASE_URL="https://raw.githubusercontent.com/ibireme/yyjson/${YYJSON_VERSION}/src"

echo "Setting up vendored dependencies..."

# --- yyjson ---
mkdir -p "$YYJSON_DIR"

if [ -f "$YYJSON_DIR/yyjson.h" ] && [ -f "$YYJSON_DIR/yyjson.c" ]; then
  echo "  yyjson: already present (skipping download)"
else
  echo "  yyjson: downloading v${YYJSON_VERSION}..."
  curl -sL "${YYJSON_BASE_URL}/yyjson.h" -o "$YYJSON_DIR/yyjson.h"
  curl -sL "${YYJSON_BASE_URL}/yyjson.c" -o "$YYJSON_DIR/yyjson.c"
  echo "  yyjson: downloaded yyjson.h and yyjson.c"
fi

echo ""
echo "Done. Vendor dependencies are ready."
echo "  yyjson: $YYJSON_DIR"
