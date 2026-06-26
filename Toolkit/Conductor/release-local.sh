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

echo "==> Validate helper bundle"
HELPER_DST="${APP_DST}/Contents/Helpers/C5hHelper"
LAUNCH_AGENT_DST="${APP_DST}/Contents/Library/LaunchAgents/com.zaai.c5h.helper.plist"

if [ ! -x "${HELPER_DST}" ]; then
  echo "ERROR: helper executable missing or not executable at ${HELPER_DST}" >&2
  echo "Check the Xcode build phase named 'Embed C5hHelper + LaunchAgent'." >&2
  exit 1
fi

if [ ! -f "${LAUNCH_AGENT_DST}" ]; then
  echo "ERROR: LaunchAgent plist missing at ${LAUNCH_AGENT_DST}" >&2
  echo "Check Resources/com.zaai.c5h.helper.plist and the helper embed build phase." >&2
  exit 1
fi

plutil -lint "${LAUNCH_AGENT_DST}" >/dev/null

if ! codesign --verify --strict --verbose=2 "${HELPER_DST}"; then
  echo "ERROR: helper code signature failed verification." >&2
  echo "Check the helper embed build phase and local signing identity." >&2
  exit 1
fi

if ! codesign --verify --deep --strict --verbose=2 "${APP_DST}"; then
  echo "ERROR: installed app code signature failed verification." >&2
  echo "Rebuild the Release app and confirm the helper is signed before app signing." >&2
  exit 1
fi

echo "==> Launch"
open "${APP_DST}"

echo
echo "Done. In C5h: Settings → LaunchAgent → Register."
echo "If 'Awaiting approval', click 'Open Login Items…' and toggle C5h on."
