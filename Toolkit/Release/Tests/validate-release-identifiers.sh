#!/bin/bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="${TESTS_DIR}/../validate-release-identifiers.sh"
FAKE_GH="${TESTS_DIR}/fake-gh.sh"
PASS_COUNT=0

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

run_validator() {
  local scenario="$1"
  shift
  FAKE_GH_SCENARIO="${scenario}" \
    GH_CLI="${FAKE_GH}" \
    GH_TOKEN="fixture-token" \
    GITHUB_REPOSITORY="ZAAI-com/C5h" \
    "${VALIDATOR}" "$@"
}

expect_success() {
  local name="$1"
  local scenario="$2"
  local version="$3"
  local build_number="$4"
  local prerelease="$5"
  local first_sparkle_release="$6"
  local expected="$7"
  local output

  if ! output="$(run_validator "${scenario}" "${version}" "${build_number}" "${prerelease}" "${first_sparkle_release}" 2>&1)"; then
    echo "${output}" >&2
    fail "${name} unexpectedly failed"
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "${expected}"; then
    echo "${output}" >&2
    fail "${name} did not report '${expected}'"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "PASS: ${name}"
}

expect_failure() {
  local name="$1"
  local scenario="$2"
  local version="$3"
  local build_number="$4"
  local prerelease="$5"
  local first_sparkle_release="$6"
  local expected="$7"
  local output

  if output="$(run_validator "${scenario}" "${version}" "${build_number}" "${prerelease}" "${first_sparkle_release}" 2>&1)"; then
    echo "${output}" >&2
    fail "${name} unexpectedly succeeded"
  fi
  if ! printf '%s\n' "${output}" | grep -Fq "${expected}"; then
    echo "${output}" >&2
    fail "${name} did not report '${expected}'"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "PASS: ${name}"
}

expect_success "Sparkle element form" "element" "2.0.0" "6" "false" "false" "highest published build is 5"
expect_failure "Reused element-form build" "element" "2.0.0" "5" "false" "false" "highest published build (5)"
expect_failure "Lower element-form build" "element" "2.0.0" "4" "false" "false" "highest published build (5)"
expect_success "Legacy enclosure attribute" "legacy" "2.0.0" "8" "false" "false" "highest published build is 7"
expect_failure "Reused legacy build" "legacy" "2.0.0" "7" "false" "false" "highest published build (7)"
expect_failure "Prerelease participates in global maximum" "mixed" "2.0.0" "6" "false" "false" "highest published build (10)"
expect_success "Build above prerelease maximum" "mixed" "2.0.0" "11" "false" "false" "highest published build is 10"
expect_failure "Highest item in multi-item appcast" "multi" "2.0.0" "12" "false" "false" "highest published build (12)"
expect_success "Build above multi-item appcast" "multi" "2.0.0" "13" "false" "false" "highest published build is 12"
expect_failure "Missing first-release override" "none" "2.0.0" "1" "false" "false" "no published appcast.xml assets exist"
expect_success "Audited first stable release" "none" "2.0.0" "1" "false" "true" "audited first_sparkle_release override"
expect_failure "First release cannot be prerelease" "none" "2.0.0" "1" "true" "true" "first Sparkle release must be stable"
expect_failure "Override rejected after publication" "element" "2.0.0" "6" "false" "true" "override is invalid"
expect_failure "Malformed published XML" "malformed" "2.0.0" "6" "false" "false" "is not well-formed XML"
expect_failure "Missing published version" "missing-version" "2.0.0" "6" "false" "false" "has no positive-integer sparkle:version"
expect_failure "Published asset download failure" "download-failure" "2.0.0" "6" "false" "false" "Could not download appcast.xml"
expect_failure "Release enumeration failure" "list-failure" "2.0.0" "6" "false" "false" "Could not enumerate published GitHub release appcasts"
expect_failure "Invalid version" "none" "02.0.0" "1" "false" "true" "version must be strict semver"
expect_failure "Invalid build number" "none" "2.0.0" "0" "false" "true" "build number must be a positive integer"

echo "All ${PASS_COUNT} release identifier validation fixtures passed."
