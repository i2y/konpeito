#!/bin/bash
# Build and run the JWM + Skija canvas demo
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Check that setup has been run
if [ ! -d "$SCRIPT_DIR/lib" ] || [ ! -d "$SCRIPT_DIR/classes" ]; then
  echo "Please run setup.sh first:"
  echo "  cd examples/jwm_canvas && bash setup.sh"
  exit 1
fi

CP="$SCRIPT_DIR/lib/jwm.jar:$SCRIPT_DIR/lib/skija-shared.jar:$SCRIPT_DIR/lib/skija-platform.jar:$SCRIPT_DIR/lib/types.jar:$SCRIPT_DIR/classes"

cd "$PROJECT_ROOT"
bundle exec ruby -Ilib bin/konpeito build --target jvm \
  --classpath "$CP" \
  --run \
  -o "$SCRIPT_DIR/canvas_demo.jar" \
  "$SCRIPT_DIR/canvas_demo.rb"
