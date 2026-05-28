#!/bin/bash
# C5h Setup Script — verifies Xcode toolchain and warms the build cache.
set -euo pipefail
cd "$(dirname "$0")/../.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1"; echo -e "        $2"; exit 1; }

echo "=== C5h — AI Coding Window Tracker — Setup ==="
echo

if ! command -v xcode-select >/dev/null 2>&1; then
  fail "xcode-select not found" "Install Xcode from the Mac App Store"
fi

if ! xcode-select -p >/dev/null 2>&1; then
  fail "Xcode CLT path not configured" "Run: sudo xcode-select --install"
fi
ok "Xcode CLT at $(xcode-select -p)"

if ! command -v xcodebuild >/dev/null 2>&1; then
  fail "xcodebuild not found" "Make sure Xcode (not just CLT) is installed"
fi

XCODE_VERSION=$(xcodebuild -version | head -n1)
ok "$XCODE_VERSION"

REQUIRED_MAJOR=26
ACTUAL_MAJOR=$(xcodebuild -version | head -n1 | sed -E 's/Xcode ([0-9]+).*/\1/')
if [ "$ACTUAL_MAJOR" -lt "$REQUIRED_MAJOR" ]; then
  warn "Xcode $ACTUAL_MAJOR found; C5h targets macOS 26 and was built against Xcode $REQUIRED_MAJOR+. Build may fail."
fi

if [ ! -d "C5h.xcworkspace" ]; then
  fail "C5h.xcworkspace missing" "Run setup from the repo root"
fi

echo
echo "Warming the Debug build cache (first build can take a while)…"
xcodebuild \
  -workspace C5h.xcworkspace \
  -scheme C5h \
  -configuration Debug \
  -destination 'platform=macOS' \
  build \
  CODE_SIGNING_ALLOWED=NO \
  | tail -n 25

echo
ok "Setup complete."
echo
echo "To open the project in Xcode:"
echo "  ./Toolkit/Conductor/run.sh"
echo
echo "Or build from the command line:"
echo "  xcodebuild -workspace C5h.xcworkspace -scheme C5h -configuration Debug build"
