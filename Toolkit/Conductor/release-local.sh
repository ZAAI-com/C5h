#!/bin/bash
# Local Release dev-loop: build Release, install into /Applications, launch.
#
# For exercising the SMAppService LaunchAgent flow during development.
# SMAppService requires Developer ID signing + the app being in /Applications,
# so a Debug build from DerivedData will always fail registration with .notFound.
#
# For a full notarized + DMG'd release, use ./Toolkit/Conductor/release.sh.
#
# Usage: ./Toolkit/Conductor/release-local.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

DERIVED="/tmp/c5h-rel"
APP_SRC="${DERIVED}/Build/Products/Release/C5h.app"
APP_DST="/Applications/C5h.app"

echo "==> Quit running C5h (if any)"
osascript -e 'tell application "C5h" to quit' 2>/dev/null || true
# Give it a moment to release file locks
sleep 1

echo "==> Build Release"
xcodebuild \
  -workspace C5h.xcworkspace \
  -scheme C5h \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  build

if [ ! -d "${APP_SRC}" ]; then
  echo "ERROR: expected ${APP_SRC} after build, not found" >&2
  exit 1
fi

echo "==> Install to /Applications"
rm -rf "${APP_DST}"
cp -R "${APP_SRC}" "${APP_DST}"

echo "==> Launch"
open "${APP_DST}"

echo
echo "Done. In C5h: Settings → LaunchAgent → Register."
echo "If 'Awaiting approval', click 'Open Login Items…' and toggle C5h on."
