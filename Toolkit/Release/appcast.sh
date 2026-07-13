#!/bin/bash
# C5h appcast generator: builds and signs the Sparkle appcast for a release.
#
# Runs AFTER release.sh so the EdDSA signature covers the final stapled DMG
# bytes. Downloads a pinned, checksum-verified Sparkle tools release, stages
# only this version's DMG, and generates build/appcast.xml with exactly one
# item (generate_appcast mounts the DMG and reads the app's real Info.plist,
# so versions and minimumSystemVersion can never drift from the bundle).
#
# Required environment (CI):
#   SPARKLE_ED_PRIVATE_KEY="base64 EdDSA private key"  # from generate_keys -x
#
# Usage: ./Toolkit/Release/appcast.sh <version> <build-number> [--ed-key-file <path>]
#   --ed-key-file reads the private key from a file instead of
#   SPARKLE_ED_PRIVATE_KEY (local testing only; never commit key files).
set -euo pipefail
cd "$(dirname "$0")/../.."

usage() {
  echo "usage: appcast.sh <version> <build-number> [--ed-key-file <path>]" >&2
}

if [ "$#" -lt 2 ]; then
  usage
  exit 2
fi

VERSION="$1"
BUILD_NUMBER="$2"
shift 2

if ! [[ "${VERSION}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "ERROR: version must be strict semver without leading zeros (for example, 2.0.0). Got: ${VERSION}" >&2
  exit 2
fi
if ! [[ "${BUILD_NUMBER}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: build number must be a positive integer (for example, 5). Got: ${BUILD_NUMBER}" >&2
  exit 2
fi

ED_KEY_FILE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ed-key-file)
      ED_KEY_FILE="${2:?--ed-key-file requires a path}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

DMG="build/C5h-${VERSION}.dmg"
APPCAST="build/appcast.xml"

# Pinned Sparkle tools release; bump the version and checksum together.
SPARKLE_TOOLS_VERSION="2.9.4"
SPARKLE_TOOLS_SHA256="ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9"
SPARKLE_TOOLS_DIR="build/sparkle-tools-${SPARKLE_TOOLS_VERSION}"
SPARKLE_TOOLS_TARBALL="build/Sparkle-${SPARKLE_TOOLS_VERSION}.tar.xz"

if [ ! -f "${DMG}" ]; then
  echo "ERROR: ${DMG} not found; run ./Toolkit/Release/release.sh ${VERSION} ${BUILD_NUMBER} first." >&2
  exit 2
fi

if [ -n "${ED_KEY_FILE}" ]; then
  if [ ! -f "${ED_KEY_FILE}" ]; then
    echo "ERROR: --ed-key-file ${ED_KEY_FILE} does not exist." >&2
    exit 2
  fi
  ED_KEY="$(cat "${ED_KEY_FILE}")"
elif [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
  ED_KEY="${SPARKLE_ED_PRIVATE_KEY}"
else
  echo "ERROR: SPARKLE_ED_PRIVATE_KEY is required (or pass --ed-key-file <path> for local testing)." >&2
  exit 2
fi

mkdir -p build

echo "==> Fetch Sparkle tools ${SPARKLE_TOOLS_VERSION}"
if [ ! -x "${SPARKLE_TOOLS_DIR}/bin/generate_appcast" ]; then
  curl -fL --retry 3 -o "${SPARKLE_TOOLS_TARBALL}" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_TOOLS_VERSION}/Sparkle-${SPARKLE_TOOLS_VERSION}.tar.xz"
  echo "${SPARKLE_TOOLS_SHA256}  ${SPARKLE_TOOLS_TARBALL}" | shasum -a 256 -c -
  rm -rf "${SPARKLE_TOOLS_DIR}"
  mkdir -p "${SPARKLE_TOOLS_DIR}"
  tar -xJf "${SPARKLE_TOOLS_TARBALL}" -C "${SPARKLE_TOOLS_DIR}"
fi

echo "==> Stage DMG"
# generate_appcast turns every update archive in the directory into a feed
# item, so stage exactly this release's DMG to get a single-item appcast.
STAGE_DIR="build/appcast-stage-${VERSION}"
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"
cp "${DMG}" "${STAGE_DIR}/"

echo "==> Generate appcast"
# The private key is passed over stdin (--ed-key-file -) so it never touches
# disk on the CI runner.
printf '%s\n' "${ED_KEY}" | "${SPARKLE_TOOLS_DIR}/bin/generate_appcast" \
  --ed-key-file - \
  -o "${APPCAST}" \
  --download-url-prefix "https://github.com/ZAAI-com/C5h/releases/download/${VERSION}/" \
  --full-release-notes-url "https://github.com/ZAAI-com/C5h/releases/tag/${VERSION}" \
  --link "https://github.com/ZAAI-com/C5h" \
  "${STAGE_DIR}"

echo "==> Validate appcast"
xmllint --noout "${APPCAST}"
# generate_appcast only WARNS when it cannot sign (e.g. key mismatch), so a
# missing EdDSA signature must hard-fail here instead of shipping a feed that
# every client rejects.
if ! grep -q 'sparkle:edSignature=' "${APPCAST}"; then
  echo "ERROR: appcast has no sparkle:edSignature; the DMG was not signed with the EdDSA key." >&2
  exit 3
fi

appcast_value() {
  local element="$1"
  local value
  value="$(xmllint --xpath "string((//*[local-name()='${element}'])[1])" "${APPCAST}")"
  if [ -z "${value}" ]; then
    value="$(xmllint --xpath "string((//*[local-name()='enclosure']/@*[local-name()='${element}'])[1])" "${APPCAST}")"
  fi
  printf '%s' "${value}"
}

APPCAST_BUILD_NUMBER="$(appcast_value version)"
APPCAST_SHORT_VERSION="$(appcast_value shortVersionString)"
if [ "${APPCAST_BUILD_NUMBER}" != "${BUILD_NUMBER}" ]; then
  echo "ERROR: appcast sparkle:version is '${APPCAST_BUILD_NUMBER}', expected build '${BUILD_NUMBER}'; the DMG embeds a different CFBundleVersion." >&2
  exit 3
fi
if [ "${APPCAST_SHORT_VERSION}" != "${VERSION}" ]; then
  echo "ERROR: appcast sparkle:shortVersionString is '${APPCAST_SHORT_VERSION}', expected '${VERSION}'; the DMG embeds a different CFBundleShortVersionString." >&2
  exit 3
fi
if ! grep -Fq "url=\"https://github.com/ZAAI-com/C5h/releases/download/${VERSION}/C5h-${VERSION}.dmg\"" "${APPCAST}"; then
  echo "ERROR: appcast enclosure URL is not the versioned DMG download URL." >&2
  exit 3
fi
if ! grep -q 'sparkle:minimumSystemVersion' "${APPCAST}"; then
  echo "ERROR: appcast is missing sparkle:minimumSystemVersion; the app's LSMinimumSystemVersion did not propagate." >&2
  exit 3
fi

echo "Done: ${APPCAST}"
