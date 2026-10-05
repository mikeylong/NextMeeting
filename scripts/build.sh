#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/NextMeeting.app"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"

# Keep compiler caches and generated files in the local project.
mkdir -p "$BUILD_DIR/module-cache" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

if [[ ! -f "$PROJECT_DIR/Resources/AppIcon.icns" || "$PROJECT_DIR/scripts/make-icon.swift" -nt "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    xcrun swiftc -module-cache-path "$BUILD_DIR/module-cache" \
        "$PROJECT_DIR/scripts/make-icon.swift" -o "$BUILD_DIR/make-icon"
    "$BUILD_DIR/make-icon" "$BUILD_DIR/NextMeeting.iconset" "$PROJECT_DIR/Resources/AppIcon.icns"
fi

SOURCES=("$PROJECT_DIR"/Sources/NextMeeting/*.swift)
if [[ ! -f "${SOURCES[0]}" ]]; then
    echo "No application sources found in Sources/NextMeeting." >&2
    exit 1
fi

xcrun swiftc -O -whole-module-optimization -parse-as-library -swift-version 6 \
    -module-name NextMeeting -module-cache-path "$BUILD_DIR/module-cache" \
    -target "$ARCH-apple-macosx14.0" -sdk "$SDK_PATH" \
    "${SOURCES[@]}" -o "$APP_DIR/Contents/MacOS/NextMeeting"

cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
plutil -lint "$APP_DIR/Contents/Info.plist" "$PROJECT_DIR/Resources/NextMeeting.entitlements"

# An explicit identifier requirement survives local rebuilds, unlike a default
# ad hoc requirement based on the executable hash. Distribution needs a real
# Apple Developer signature; this signature is for local development.
codesign --force --sign - --identifier systems.surfaces.NextMeeting \
    --requirements '=designated => identifier "systems.surfaces.NextMeeting"' \
    --entitlements "$PROJECT_DIR/Resources/NextMeeting.entitlements" \
    "$APP_DIR"
codesign --verify --strict "$APP_DIR"
echo "Built $APP_DIR"
