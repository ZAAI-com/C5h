#!/bin/bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY_ROOT="$(cd "${TESTS_DIR}/../../.." && pwd)"
# Derived from appcast.sh rather than duplicated: a second literal here would
# silently keep probing the old tools path after the pin is bumped, failing
# every release at this gate even though appcast generation succeeded.
APPCAST_SH="${TESTS_DIR}/../appcast.sh"
SPARKLE_TOOLS_VERSION="$(
  sed -n 's/^SPARKLE_TOOLS_VERSION="\(.*\)"$/\1/p' "${APPCAST_SH}" | head -n 1
)"
if [ -z "${SPARKLE_TOOLS_VERSION}" ]; then
  echo "FAIL: could not read SPARKLE_TOOLS_VERSION from ${APPCAST_SH}" >&2
  exit 1
fi
SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-${REPOSITORY_ROOT}/build/sparkle-tools-${SPARKLE_TOOLS_VERSION}/bin/sign_update}"
PASS_COUNT=0

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

if [ ! -x "${SIGN_UPDATE}" ]; then
  fail "${SIGN_UPDATE} is unavailable; run appcast.sh once to install the pinned Sparkle tools"
fi
if ! command -v openssl >/dev/null 2>&1; then
  fail "openssl is required to generate a disposable EdDSA seed"
fi

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/c5h-appcast-signature.XXXXXX")"
trap 'rm -rf "${TEST_DIR}"' EXIT

# Sparkle's current private-key export format is a base64-encoded 32-byte seed.
# This key exists only for this test and never touches the login Keychain.
TEST_KEY="$(openssl rand -base64 32 | tr -d '\n')"
UNSIGNED_FEED="${TEST_DIR}/unsigned.xml"
SIGNED_FEED="${TEST_DIR}/signed.xml"
TAMPERED_FEED="${TEST_DIR}/tampered.xml"

printf '%s\n' \
  '<?xml version="1.0" encoding="utf-8"?>' \
  '<rss version="2.0"><channel><title>C5h Test</title></channel></rss>' \
  > "${UNSIGNED_FEED}"
cp "${UNSIGNED_FEED}" "${SIGNED_FEED}"

printf '%s\n' "${TEST_KEY}" | "${SIGN_UPDATE}" --ed-key-file - "${SIGNED_FEED}"
if ! grep -q '<!-- sparkle-signatures:' "${SIGNED_FEED}"; then
  fail "sign_update did not embed a feed signature"
fi
if ! printf '%s\n' "${TEST_KEY}" | "${SIGN_UPDATE}" --verify --ed-key-file - "${SIGNED_FEED}" >/dev/null; then
  fail "a correctly signed feed did not verify"
fi
PASS_COUNT=$((PASS_COUNT + 1))
echo "PASS: correctly signed feed"

if printf '%s\n' "${TEST_KEY}" | "${SIGN_UPDATE}" --verify --ed-key-file - "${UNSIGNED_FEED}" >/dev/null 2>&1; then
  fail "an unsigned feed unexpectedly verified"
fi
PASS_COUNT=$((PASS_COUNT + 1))
echo "PASS: missing feed signature"

cp "${SIGNED_FEED}" "${TAMPERED_FEED}"
sed -i '' 's/C5h Test/C5h Tampered/' "${TAMPERED_FEED}"
if printf '%s\n' "${TEST_KEY}" | "${SIGN_UPDATE}" --verify --ed-key-file - "${TAMPERED_FEED}" >/dev/null 2>&1; then
  fail "a modified signed feed unexpectedly verified"
fi
PASS_COUNT=$((PASS_COUNT + 1))
echo "PASS: tampered feed"

echo "All ${PASS_COUNT} appcast signature fixtures passed."
