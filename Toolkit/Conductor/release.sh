#!/bin/bash
# C5h release script — archives, signs, notarizes, and packages a DMG.
#
# Required environment:
#   DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
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

mkdir -p build

echo "==> Build helper executable"
swift build --package-path Packages/C5hHelper -c release

echo "==> Archive main app"
xcodebuild \
  -workspace "${WORKSPACE}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "${ARCHIVE}" \
  archive \
  CODE_SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION}" \
  ENABLE_HARDENED_RUNTIME=YES \
  MARKETING_VERSION="${VERSION}"

echo "==> Embed helper binary"
HELPER_DST="${ARCHIVE}/Products/Applications/${SCHEME}.app/Contents/Helpers"
mkdir -p "${HELPER_DST}"
cp Packages/C5hHelper/.build/release/C5hHelper "${HELPER_DST}/C5hHelper"
codesign --force --options runtime --sign "${DEVELOPER_ID_APPLICATION}" \
  "${HELPER_DST}/C5hHelper"

echo "==> Embed LaunchAgent plist"
LA_DST="${ARCHIVE}/Products/Applications/${SCHEME}.app/Contents/Library/LaunchAgents"
mkdir -p "${LA_DST}"
cp Resources/com.zaai.c5h.helper.plist "${LA_DST}/"

echo "==> Re-sign main app bundle (helper changed)"
codesign --force --options runtime --deep --sign "${DEVELOPER_ID_APPLICATION}" \
  "${ARCHIVE}/Products/Applications/${SCHEME}.app"

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

if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
  echo "==> Notarize"
  ditto -c -k --keepParent "${EXPORT_DIR}/${SCHEME}.app" build/notarize.zip
  xcrun notarytool submit build/notarize.zip \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait
  xcrun stapler staple "${EXPORT_DIR}/${SCHEME}.app"
fi

echo "==> Build DMG"
hdiutil create -volname "C5h" -srcfolder "${EXPORT_DIR}" -ov -format UDZO "${DMG}"

echo "Done: ${DMG}"
