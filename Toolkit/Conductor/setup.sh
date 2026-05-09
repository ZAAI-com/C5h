#!/bin/bash
# C5h Setup Script
# Checks prerequisites and installs frontend dependencies.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

check_pass() {
    echo -e "${GREEN}[OK]${NC} $1"
}

check_fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "        $2"
    exit 1
}

echo "========================================"
echo "  C5h - AI Tool Usage Tracker Setup"
echo "========================================"
echo ""
echo "Project directory: $PROJECT_DIR"
echo ""
echo "Checking prerequisites..."
echo ""

echo "1. Rust toolchain"
if command -v rustc &>/dev/null; then
    check_pass "Rust $(rustc --version | awk '{print $2}')"
else
    check_fail "Rust not installed" "Install from: https://rustup.rs"
fi

if command -v cargo &>/dev/null; then
    check_pass "Cargo $(cargo --version | awk '{print $2}')"
else
    check_fail "Cargo not installed" "Install Rust toolchain from: https://rustup.rs"
fi

echo ""
echo "2. Bun package manager"
if command -v bun &>/dev/null; then
    check_pass "Bun $(bun --version)"
else
    check_fail "Bun not installed" "Install from: https://bun.sh"
fi

echo ""
echo "3. Xcode Command Line Tools"
if [[ "$(uname -s)" == "Darwin" ]]; then
    if xcode-select -p &>/dev/null; then
        check_pass "Xcode CLT installed"
    else
        check_fail "Xcode CLT not installed" "Run: xcode-select --install"
    fi
else
    check_pass "Xcode CLT check skipped (non-macOS host)"
fi

echo ""
echo "--- Installing frontend dependencies ---"
bun install
check_pass "Frontend dependencies installed"

echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "Next step:"
echo "  ./Toolkit/Conductor/run.sh"
echo ""
