#!/bin/bash
# C5h Development Server
# Starts Tauri in development mode with hot-reload.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

DEV_PORT="${CONDUCTOR_PORT:-1420}"
export VITE_DEV_PORT="$DEV_PORT"

TEMP_CONFIG="$(mktemp -t c5h-tauri-dev-config.XXXXXX.json)"
cleanup() {
    rm -f "$TEMP_CONFIG"
}
trap cleanup EXIT

cat > "$TEMP_CONFIG" <<EOF
{
  "build": {
    "devUrl": "http://localhost:${DEV_PORT}"
  }
}
EOF

if [ ! -d "node_modules" ]; then
    echo "node_modules missing — running setup first..."
    "$SCRIPT_DIR/setup.sh"
fi

echo "========================================"
echo "  C5h Dev Server (bun tauri dev)"
echo "========================================"
echo ""
echo "Project directory: $PROJECT_DIR"
echo "Dev URL: http://localhost:$DEV_PORT"
echo "Press Ctrl-C to stop."
echo ""

bun tauri dev --config "$TEMP_CONFIG"
