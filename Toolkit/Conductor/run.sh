#!/bin/bash
# C5h Run Script — opens the workspace in Xcode for interactive dev.
# Agents that just need to build can use:
#   xcodebuild -workspace C5h.xcworkspace -scheme C5h -configuration Debug build
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ ! -d "C5h.xcworkspace" ]; then
  echo "C5h.xcworkspace missing. Run ./Toolkit/Conductor/setup.sh first." >&2
  exit 1
fi

if command -v xed >/dev/null 2>&1; then
  exec xed C5h.xcworkspace
else
  exec open C5h.xcworkspace
fi
