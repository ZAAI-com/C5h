#!/bin/bash
# Validate release identifiers against every published Sparkle appcast.
#
# Usage:
#   validate-release-identifiers.sh <version> <build-number> <prerelease> <first-sparkle-release>
#
# Required environment:
#   GITHUB_REPOSITORY  GitHub owner/repository, provided automatically in Actions
#   GH_TOKEN           Token used by the GitHub CLI
set -euo pipefail

export LC_ALL=C

usage() {
  echo "usage: validate-release-identifiers.sh <version> <build-number> <prerelease> <first-sparkle-release>" >&2
}

if [ "$#" -ne 4 ]; then
  usage
  exit 2
fi

VERSION="$1"
BUILD_NUMBER="$2"
PRERELEASE="$3"
FIRST_SPARKLE_RELEASE="$4"
GH_CLI="${GH_CLI:-gh}"

if ! [[ "${VERSION}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "ERROR: version must be strict semver without leading zeros (for example, 2.0.0). Got: ${VERSION}" >&2
  exit 2
fi
if ! [[ "${BUILD_NUMBER}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: build number must be a positive integer (for example, 5). Got: ${BUILD_NUMBER}" >&2
  exit 2
fi
case "${PRERELEASE}" in
  true|false) ;;
  *)
    echo "ERROR: prerelease must be true or false. Got: ${PRERELEASE}" >&2
    exit 2
    ;;
esac
case "${FIRST_SPARKLE_RELEASE}" in
  true|false) ;;
  *)
    echo "ERROR: first-sparkle-release must be true or false. Got: ${FIRST_SPARKLE_RELEASE}" >&2
    exit 2
    ;;
esac
if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "ERROR: GITHUB_REPOSITORY is required." >&2
  exit 2
fi
if ! command -v "${GH_CLI}" >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI not found: ${GH_CLI}" >&2
  exit 2
fi
if ! command -v xmllint >/dev/null 2>&1; then
  echo "ERROR: xmllint not found in PATH; published appcast validation requires xmllint (libxml2)." >&2
  exit 2
fi

decimal_greater_than() {
  local candidate="$1"
  local baseline="$2"

  if [ "${#candidate}" -gt "${#baseline}" ]; then
    return 0
  fi
  if [ "${#candidate}" -lt "${#baseline}" ]; then
    return 1
  fi
  [[ "${candidate}" > "${baseline}" ]]
}

VALIDATION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/c5h-release-validation.XXXXXX")"
cleanup() {
  rm -rf "${VALIDATION_DIR}"
}
trap cleanup EXIT HUP INT TERM

ASSET_MANIFEST="${VALIDATION_DIR}/appcasts.tsv"
# The $release token below is a jq variable, not a shell expansion.
# shellcheck disable=SC2016
if ! "${GH_CLI}" api --paginate \
  "repos/${GITHUB_REPOSITORY}/releases?per_page=100" \
  --jq '.[] | select(.draft == false) | . as $release | .assets[]? | select(.name == "appcast.xml") | [$release.tag_name, ($release.prerelease | tostring), (.id | tostring)] | @tsv' \
  > "${ASSET_MANIFEST}"; then
  echo "ERROR: Could not enumerate published GitHub release appcasts; refusing to skip the monotonic build-number check." >&2
  exit 1
fi

if [ ! -s "${ASSET_MANIFEST}" ]; then
  if [ "${FIRST_SPARKLE_RELEASE}" != "true" ]; then
    echo "ERROR: GitHub reports that no published appcast.xml assets exist. Refusing to skip the monotonic build-number check without first_sparkle_release=true." >&2
    exit 1
  fi
  if [ "${PRERELEASE}" = "true" ]; then
    echo "ERROR: The first Sparkle release must be stable so releases/latest serves its appcast. Disable prerelease and rerun." >&2
    exit 1
  fi
  echo "::notice::Using the audited first_sparkle_release override; GitHub confirms that no published appcast.xml asset exists."
  exit 0
fi

if [ "${FIRST_SPARKLE_RELEASE}" = "true" ]; then
  echo "ERROR: The first_sparkle_release override is invalid because published appcast.xml assets already exist:" >&2
  while IFS=$'\t' read -r release_tag release_prerelease asset_id; do
    echo "  ${release_tag} (prerelease=${release_prerelease}, asset=${asset_id})" >&2
  done < "${ASSET_MANIFEST}"
  exit 1
fi

PUBLISHED_BUILD=""
ASSET_COUNT=0
while IFS=$'\t' read -r release_tag release_prerelease asset_id; do
  if [ -z "${release_tag}" ] || ! [[ "${release_prerelease}" =~ ^(true|false)$ ]] || ! [[ "${asset_id}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: GitHub returned an invalid appcast asset record: ${release_tag}<tab>${release_prerelease}<tab>${asset_id}" >&2
    exit 1
  fi

  ASSET_COUNT=$((ASSET_COUNT + 1))
  APPCAST_FILE="${VALIDATION_DIR}/appcast-${ASSET_COUNT}.xml"
  if ! "${GH_CLI}" api \
    -H "Accept: application/octet-stream" \
    "repos/${GITHUB_REPOSITORY}/releases/assets/${asset_id}" \
    > "${APPCAST_FILE}"; then
    echo "ERROR: Could not download appcast.xml for release ${release_tag} (asset ${asset_id}); refusing to skip it." >&2
    exit 1
  fi
  if ! xmllint --nonet --noout "${APPCAST_FILE}"; then
    echo "ERROR: appcast.xml for release ${release_tag} (asset ${asset_id}) is not well-formed XML; refusing to skip it." >&2
    exit 1
  fi

  if ! ITEM_COUNT="$(xmllint --nonet --xpath "count(//*[local-name()='item'])" "${APPCAST_FILE}" 2>/dev/null)"; then
    echo "ERROR: Could not inspect appcast.xml items for release ${release_tag} (asset ${asset_id})." >&2
    exit 1
  fi
  if ! [[ "${ITEM_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: appcast.xml for release ${release_tag} (asset ${asset_id}) contains no update items." >&2
    exit 1
  fi

  ITEM_INDEX=1
  while [ "${ITEM_INDEX}" -le "${ITEM_COUNT}" ]; do
    if ! APPCAST_BUILD="$(xmllint --nonet --xpath \
      "normalize-space(string((//*[local-name()='item'])[${ITEM_INDEX}]/*[local-name()='version'][1]))" \
      "${APPCAST_FILE}" 2>/dev/null)"; then
      echo "ERROR: Could not parse sparkle:version element ${ITEM_INDEX} for release ${release_tag} (asset ${asset_id})." >&2
      exit 1
    fi
    if [ -z "${APPCAST_BUILD}" ]; then
      if ! APPCAST_BUILD="$(xmllint --nonet --xpath \
        "normalize-space(string((//*[local-name()='item'])[${ITEM_INDEX}]/*[local-name()='enclosure'][1]/@*[local-name()='version']))" \
        "${APPCAST_FILE}" 2>/dev/null)"; then
        echo "ERROR: Could not parse enclosure sparkle:version attribute ${ITEM_INDEX} for release ${release_tag} (asset ${asset_id})." >&2
        exit 1
      fi
    fi
    if ! [[ "${APPCAST_BUILD}" =~ ^[1-9][0-9]*$ ]]; then
      echo "ERROR: appcast.xml item ${ITEM_INDEX} for release ${release_tag} (asset ${asset_id}) has no positive-integer sparkle:version." >&2
      exit 1
    fi

    if [ -z "${PUBLISHED_BUILD}" ] || decimal_greater_than "${APPCAST_BUILD}" "${PUBLISHED_BUILD}"; then
      PUBLISHED_BUILD="${APPCAST_BUILD}"
    fi
    ITEM_INDEX=$((ITEM_INDEX + 1))
  done
done < "${ASSET_MANIFEST}"

if [ -z "${PUBLISHED_BUILD}" ]; then
  echo "ERROR: Published appcast assets yielded no build numbers; refusing to skip the monotonic build-number check." >&2
  exit 1
fi
if ! decimal_greater_than "${BUILD_NUMBER}" "${PUBLISHED_BUILD}"; then
  echo "ERROR: Build number must be strictly greater than the highest published build (${PUBLISHED_BUILD}); a lower or reused number poisons the Sparkle feed. Got: ${BUILD_NUMBER}" >&2
  exit 1
fi

echo "::notice::Validated build ${BUILD_NUMBER} against ${ASSET_COUNT} published appcast asset(s); highest published build is ${PUBLISHED_BUILD}."
