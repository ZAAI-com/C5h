#!/bin/bash
# C5h dev-install script: builds the Debug app and installs it into /Applications
# as "C5h Dev.app", so the dev build can live next to the production "C5h.app".
#
# The dev build is a separate macOS app (bundle id com.zaai.c5h.debug, name
# "C5h Dev", distinct icon) but intentionally shares the SAME data directory as
# production (~/Library/Application Support/C5h), so it reads/writes the real
# database. Keep only one background helper running at a time to avoid running a
# due scheduled prompt twice against the shared DB.
#
# CAVEAT: the dev subprocess helper (Settings > Helper > Debug subprocess runner)
# resolves its binary relative to the process working directory
# (Packages/C5hHelper/.build/...), so it only works when the app is launched
# FROM Xcode at the repo root. A copy launched from /Applications has working
# directory "/" and will report "Helper binary missing." Use this installed copy
# to launch the distinct-icon UI against the shared production DB; run the app
# from Xcode when you need the dev scheduler/helper loop.
#
# Usage: ./Toolkit/Conductor/install-dev.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

SCHEME="C5h"
WORKSPACE="C5h.xcworkspace"
DERIVED="build/DevInstall"
PRODUCT="C5h Dev.app"
DEST="/Applications/${PRODUCT}"

if [ ! -d "$WORKSPACE" ]; then
  echo "ERROR: $WORKSPACE missing. Run ./Toolkit/Conductor/setup.sh first." >&2
  exit 1
fi

echo "==> Build helper (debug) so the dev subprocess runner can find it"
swift build --package-path Packages/C5hHelper

echo "==> Build Debug app"
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  build

SRC="${DERIVED}/Build/Products/Debug/${PRODUCT}"
if [ ! -d "$SRC" ]; then
  echo "ERROR: built app not found at $SRC" >&2
  exit 1
fi

echo "==> Install to ${DEST}"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "Installed ${DEST}"
echo "Launch it from /Applications (UI only), or run from Xcode for the dev helper loop."
