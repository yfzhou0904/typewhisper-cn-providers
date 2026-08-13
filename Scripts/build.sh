#!/bin/bash
# Build the TypeWhisperCNProviders .bundle and install it into TypeWhisper's Plugins dir.
# Usage: ./Scripts/build.sh [--install | --symlink]
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="TypeWhisperCNProviders"
CONFIG="Release"
DERIVED="build/DerivedData"
PLUGINS_DIR="$HOME/Library/Application Support/TypeWhisper/Plugins"
PRODUCT="$DERIVED/Build/Products/$CONFIG/TypeWhisperCNProviders.bundle"

echo "==> Generating Xcode project (xcodegen)"
xcodegen generate

echo "==> Building $SCHEME ($CONFIG)"
xcodebuild -project TypeWhisperCNProviders.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  build

if [ ! -d "$PRODUCT" ]; then
  echo "ERROR: bundle not found at $PRODUCT" >&2
  exit 1
fi

# Embed the dynamic TypeWhisperPluginSDK framework so the bundle is self-contained
# (rpath @executable_path/../Frameworks is already baked into the executable).
FRAMEWORKS_SRC="$DERIVED/Build/Products/$CONFIG/PackageFrameworks"
if [ -d "$FRAMEWORKS_SRC" ]; then
  mkdir -p "$PRODUCT/Contents/Frameworks"
  cp -R "$FRAMEWORKS_SRC/"*.framework "$PRODUCT/Contents/Frameworks/"
  echo "==> Embedded SDK framework(s) into bundle"
fi

# Re-sign the bundle ad-hoc AFTER embedding the framework so the code seal
# covers all nested resources (macOS won't load a broken-sealed bundle).
codesign --force --sign - "$PRODUCT"
echo "==> Re-signed bundle (ad-hoc)"

echo "==> Bundle built: $PRODUCT"
echo "    Contents:"
find "$PRODUCT" -maxdepth 3 -type d -o -type f | sed "s|$PRODUCT|.|" | head -40

mkdir -p "$PLUGINS_DIR"

if [ "${1:-}" = "--symlink" ]; then
  ln -sfn "$(cd "$PRODUCT" && pwd)" "$PLUGINS_DIR/TypeWhisperCNProviders.bundle"
  echo "==> Symlinked into $PLUGINS_DIR/TypeWhisperCNProviders.bundle"
elif [ "${1:-}" = "--install" ]; then
  rm -rf "$PLUGINS_DIR/TypeWhisperCNProviders.bundle"
  cp -R "$PRODUCT" "$PLUGINS_DIR/TypeWhisperCNProviders.bundle"
  echo "==> Copied into $PLUGINS_DIR/TypeWhisperCNProviders.bundle"
else
  echo "==> (Not installed. Re-run with --install or --symlink to place it in TypeWhisper.)"
fi
