#!/usr/bin/env bash
# Render the C5h Homebrew Cask from the checked-in template.
#
# Usage:
#   render-cask.sh VERSION --sha <hex> [--out PATH]
#
# Reads:    Toolkit/Homebrew/cask.rb.tmpl
# Writes:   stdout, or --out PATH
#
# Used both locally (for brew style + brew install --cask testing against a
# draft release) and from the S3 publishing workflow. C5h ships a single
# universal DMG, so there is one SHA256 (no arm/intel split).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/cask.rb.tmpl"

if [ ! -r "$TEMPLATE" ]; then
    echo "ERROR: Cask template not readable: $TEMPLATE" >&2
    exit 1
fi

VERSION=""
SHA=""
OUT=""

usage() {
    cat <<EOF >&2
Usage: $0 VERSION --sha <hex> [--out PATH]

  VERSION    Strict semver, no leading zeros, no v prefix (e.g. 0.5.0)
  --sha      SHA256 of the DMG (64 hex chars)
  --out PATH Write to PATH instead of stdout
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --sha)
            if [ $# -lt 2 ]; then
                echo "ERROR: --sha requires a value" >&2; usage; exit 2
            fi
            SHA="$2"; shift 2
            ;;
        --out)
            if [ $# -lt 2 ]; then
                echo "ERROR: --out requires a value" >&2; usage; exit 2
            fi
            OUT="$2"; shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        --*)       echo "ERROR: unknown flag $1" >&2; usage; exit 2 ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$1"; shift
            else
                echo "ERROR: unexpected positional arg $1" >&2; usage; exit 2
            fi
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "ERROR: VERSION is required" >&2; usage; exit 2
fi
if ! [[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "ERROR: VERSION must be strict semver (e.g. 0.5.0), got '$VERSION'" >&2
    exit 2
fi
if ! [[ "$SHA" =~ ^[0-9a-f]{64}$ ]]; then
    echo "ERROR: --sha must be 64 lowercase hex chars" >&2; exit 2
fi

RENDERED="$(sed \
    -e "s|VERSION_PLACEHOLDER|${VERSION}|g" \
    -e "s|SHA_PLACEHOLDER|${SHA}|g" \
    "$TEMPLATE")"

if [ -n "$OUT" ]; then
    printf '%s\n' "$RENDERED" > "$OUT"
else
    printf '%s\n' "$RENDERED"
fi
