#!/bin/bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="${TESTS_DIR}/Fixtures"
SCENARIO="${FAKE_GH_SCENARIO:?FAKE_GH_SCENARIO is required}"

if [ "$#" -lt 2 ] || [ "$1" != "api" ]; then
  echo "fake-gh: expected an api command" >&2
  exit 2
fi
shift

ENDPOINT=""
for argument in "$@"; do
  case "${argument}" in
    repos/*/releases\?per_page=100|repos/*/releases/assets/*)
      ENDPOINT="${argument}"
      ;;
  esac
done

case "${ENDPOINT}" in
  */releases\?per_page=100)
    if [ "${SCENARIO}" = "list-failure" ]; then
      echo "fake-gh: simulated release enumeration failure" >&2
      exit 1
    fi
    if [[ "$*" != *"select(.draft == false)"* ]]; then
      echo "fake-gh: release query must exclude drafts" >&2
      exit 2
    fi
    if [[ "$*" != *"--paginate"* ]] || [[ "$*" != *'select(.name == "appcast.xml")'* ]]; then
      echo "fake-gh: release query must paginate and select appcast.xml assets" >&2
      exit 2
    fi
    if [[ "$*" == *"prerelease == false"* ]]; then
      echo "fake-gh: release query must not exclude prereleases" >&2
      exit 2
    fi
    case "${SCENARIO}" in
      none)
        ;;
      element)
        printf '1.0.0\tfalse\t105\n'
        ;;
      legacy)
        printf '1.0.1\tfalse\t107\n'
        ;;
      mixed)
        printf '1.0.0\tfalse\t105\n'
        printf '1.1.0\ttrue\t110\n'
        ;;
      multi)
        printf '1.2.0\tfalse\t112\n'
        ;;
      malformed)
        printf '1.3.0\tfalse\t999\n'
        ;;
      missing-version)
        printf '1.4.0\tfalse\t998\n'
        ;;
      download-failure)
        printf '1.5.0\tfalse\t997\n'
        ;;
      *)
        echo "fake-gh: unknown list scenario ${SCENARIO}" >&2
        exit 2
        ;;
    esac
    ;;
  */releases/assets/*)
    if [[ "$*" != *"Accept: application/octet-stream"* ]]; then
      echo "fake-gh: asset downloads must request binary content" >&2
      exit 2
    fi
    ASSET_ID="${ENDPOINT##*/}"
    case "${ASSET_ID}" in
      105)
        cat "${FIXTURES_DIR}/element-build-5.xml"
        ;;
      107)
        cat "${FIXTURES_DIR}/legacy-build-7.xml"
        ;;
      110)
        cat "${FIXTURES_DIR}/element-build-10.xml"
        ;;
      112)
        cat "${FIXTURES_DIR}/multi-builds-9-12.xml"
        ;;
      998)
        cat "${FIXTURES_DIR}/missing-version.xml"
        ;;
      999)
        cat "${FIXTURES_DIR}/malformed-appcast.xml"
        ;;
      997)
        echo "fake-gh: simulated asset download failure" >&2
        exit 1
        ;;
      *)
        echo "fake-gh: unknown asset ${ASSET_ID}" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "fake-gh: unexpected endpoint in: $*" >&2
    exit 2
    ;;
esac
