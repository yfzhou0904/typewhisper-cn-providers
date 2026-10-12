#!/bin/bash
# Calls Agent Plan with a short WAV using the plugin's production transport.
# Run Scripts/build.sh first to produce the SDK framework.
set -euo pipefail
cd "$(dirname "$0")/.."

PRODUCTS="build/DerivedData/Build/Products/Release"
FRAMEWORKS="$PRODUCTS/PackageFrameworks"
if [ ! -d "$FRAMEWORKS/TypeWhisperPluginSDK.framework" ]; then
  echo "Build the plugin first: ./Scripts/build.sh" >&2
  exit 1
fi

xcrun swiftc -parse-as-library \
  Sources/*.swift Sources/Support/*.swift Scripts/smoke-agent-plan.swift \
  -I "$PRODUCTS" -F "$FRAMEWORKS" -framework TypeWhisperPluginSDK \
  -Xlinker -rpath -Xlinker "$(pwd)/$FRAMEWORKS" \
  -o build/smoke-agent-plan
exec build/smoke-agent-plan "$@"
