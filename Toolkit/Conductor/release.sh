#!/bin/bash
# C5h release script: archives, signs, notarizes, and packages a DMG.
#
# Required environment:
#   DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
#
# Required for notarization (the build fails without them, unless
# ALLOW_UNNOTARIZED=1 is set for a local/dev DMG):
#   APPLE_ID="apple-id@example.com"
#   APPLE_TEAM_ID="ABCDEFGHIJ"
#   APPLE_APP_PASSWORD="app-specific password"  # for notarytool
#
# Usage: ./Toolkit/Conductor/release.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION="${1:?usage: release.sh <version>}"
SCHEME="C5h"
WORKSPACE="C5h.xcworkspace"
ARCHIVE="build/C5h-${VERSION}.xcarchive"
EXPORT_DIR="build/export-${VERSION}"
DMG="build/C5h-${VERSION}.dmg"

if [ -z "${DEVELOPER_ID_APPLICATION:-}" ]; then
  echo "ERROR: DEVELOPER_ID_APPLICATION is required for a signed build." >&2
  exit 2
fi

# Notarization is mandatory for distributable builds. If any credential is
# missing the build fails fast, so we never silently ship an unnotarized DMG.
# Set ALLOW_UNNOTARIZED=1 to opt out for local/dev DMGs only.
NOTARIZE=1
if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ] || [ -z "${APPLE_APP_PASSWORD:-}" ]; then
  if [ "${ALLOW_UNNOTARIZED:-0}" = "1" ]; then
    echo "WARNING: APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD missing; building an UNNOTARIZED DMG (ALLOW_UNNOTARIZED=1). Do not distribute this build." >&2
    NOTARIZE=0
  else
    echo "ERROR: notarization requires APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD." >&2
    echo "       Set ALLOW_UNNOTARIZED=1 to build an unnotarized dev DMG instead." >&2
    exit 2
  fi
fi

mkdir -p build

echo "==> Build universal helper executable"
# The main app archives universal (arm64 + x86_64), so the embedded helper must
# match. Build each slice explicitly and combine with lipo so the shipped helper
# runs natively on both architectures.
swift build --package-path Packages/C5hHelper -c release --arch arm64
swift build --package-path Packages/C5hHelper -c release --arch x86_64
lipo -create \
  Packages/C5hHelper/.build/arm64-apple-macosx/release/C5hHelper \
  Packages/C5hHelper/.build/x86_64-apple-macosx/release/C5hHelper \
  -output build/C5hHelper-universal
lipo -info build/C5hHelper-universal

# SPM dependency bundle targets (e.g. GRDB's GRDB_GRDB resource bundle) do not
# inherit the app target's DEVELOPMENT_TEAM and fail archive signing without it,
# so the team is passed on the command line. Prefer APPLE_TEAM_ID; otherwise fall
# back to the 10-character team embedded in the Developer ID identity ("(TEAMID)").
TEAM_ID="${APPLE_TEAM_ID:-}"
if [ -z "$TEAM_ID" ]; then
  TEAM_ID="$(printf '%s' "$DEVELOPER_ID_APPLICATION" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')"
fi
if [ -z "$TEAM_ID" ]; then
  echo "ERROR: could not determine the signing team; set APPLE_TEAM_ID or include it in DEVELOPER_ID_APPLICATION." >&2
  exit 2
fi

echo "==> Archive main app"
xcodebuild \
  -workspace "${WORKSPACE}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "${ARCHIVE}" \
  archive \
  CODE_SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION}" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  ENABLE_HARDENED_RUNTIME=YES \
  MARKETING_VERSION="${VERSION}"

echo "==> Embed helper binary"
HELPER_DST="${ARCHIVE}/Products/Applications/${SCHEME}.app/Contents/Helpers"
mkdir -p "${HELPER_DST}"
cp build/C5hHelper-universal "${HELPER_DST}/C5hHelper"
codesign --force --options runtime --sign "${DEVELOPER_ID_APPLICATION}" \
  "${HELPER_DST}/C5hHelper"

echo "==> Embed LaunchAgent plist"
LA_DST="${ARCHIVE}/Products/Applications/${SCHEME}.app/Contents/Library/LaunchAgents"
mkdir -p "${LA_DST}"
cp Resources/com.zaai.c5h.helper.plist "${LA_DST}/"

echo "==> Re-sign main app bundle (helper changed)"
codesign --force --options runtime --deep --sign "${DEVELOPER_ID_APPLICATION}" \
  "${ARCHIVE}/Products/Applications/${SCHEME}.app"

echo "==> Verify universal slices"
# Run on every build (notarized or not) so an architecture or signing regression
# fails fast instead of shipping an inconsistent bundle.
APP="${ARCHIVE}/Products/Applications/${SCHEME}.app"
lipo "${APP}/Contents/MacOS/${SCHEME}" -verify_arch arm64 x86_64
lipo "${APP}/Contents/Helpers/C5hHelper" -verify_arch arm64 x86_64
codesign --verify --deep --strict --verbose=2 "${APP}"

echo "==> Export"
cat > build/export-options.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
</dict>
</plist>
EOF
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist build/export-options.plist

if [ "${NOTARIZE}" = "1" ]; then
  echo "==> Notarize app"
  ditto -c -k --keepParent "${EXPORT_DIR}/${SCHEME}.app" build/notarize.zip
  xcrun notarytool submit build/notarize.zip \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait
  xcrun stapler staple "${EXPORT_DIR}/${SCHEME}.app"
fi

echo "==> Build DMG"
# Stage only the .app so the disk image root does not also ship the exporter's
# DistributionSummary.plist / ExportOptions.plist / Packaging.log side files.
DMG_STAGE="build/dmg-${VERSION}"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"
cp -R "${EXPORT_DIR}/${SCHEME}.app" "${DMG_STAGE}/"
hdiutil create -volname "C5h" -srcfolder "${DMG_STAGE}" -ov -format UDZO "${DMG}"

if [ "${NOTARIZE}" = "1" ]; then
  echo "==> Notarize DMG"
  # The DMG needs its own notarization ticket before it can be stapled; the app
  # ticket stapled above does not cover the disk image itself.
  xcrun notarytool submit "${DMG}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait

  echo "==> Staple DMG"
  # Stapling the DMG lets Gatekeeper validate the downloaded disk image offline
  # (e.g. a Homebrew cask install).
  xcrun stapler staple "${DMG}"

  echo "==> Verify notarization"
  # Fail the build if the notarization ticket did not actually take, instead of
  # silently shipping a DMG that triggers Gatekeeper warnings on install.
  xcrun stapler validate "${EXPORT_DIR}/${SCHEME}.app"
  xcrun stapler validate "${DMG}"
  codesign --verify --deep --strict --verbose=2 "${EXPORT_DIR}/${SCHEME}.app"
fi

echo "==> Compute SHA256"
shasum -a 256 "${DMG}" | awk '{print $1}' > "${DMG}.sha256"

echo "Done: ${DMG} (sha256: $(cat "${DMG}.sha256"))"
