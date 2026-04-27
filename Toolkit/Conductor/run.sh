#!/bin/bash
# C5h Development Server
# Starts Tauri in development mode with hot-reload.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

if [ ! -d "node_modules" ]; then
    echo "node_modules missing — running setup first..."
    "$SCRIPT_DIR/setup.sh"
fi

echo "========================================"
echo "  C5h Dev Server (bun tauri dev)"
echo "========================================"
echo ""
echo "Project directory: $PROJECT_DIR"
echo "Press Ctrl-C to stop."
echo ""

exec bun tauri dev
