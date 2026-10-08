#!/bin/bash
set -euo pipefail

[[ $# -le 1 ]] || { echo 'Usage: scripts/build.sh [--release]' >&2; exit 1; }
BUILD_KIND="local"
case "${1:-}" in
    '') ;;
    --release) BUILD_KIND="release" ;;
    *) echo 'Usage: scripts/build.sh [--release]' >&2; exit 1 ;;
esac

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/Next Meeting.app"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
SWIFT_FLAGS=(-O -whole-module-optimization -parse-as-library -swift-version 6
    -module-name NextMeeting -target "$ARCH-apple-macosx14.0")

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

xcrun swiftc "${SWIFT_FLAGS[@]}" -module-cache-path "$BUILD_DIR/module-cache" \
    -sdk "$SDK_PATH" \
    "${SOURCES[@]}" -o "$APP_DIR/Contents/MacOS/NextMeeting"

cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ "$BUILD_KIND" == local ]]; then
    BUILD_IDENTIFIER="$("$PROJECT_DIR/scripts/build-identifier.sh" "$PROJECT_DIR" \
        "$(xcrun swiftc --version)" "$(xcrun --sdk macosx --show-sdk-version)" \
        "$(xcrun --sdk macosx --show-sdk-build-version)" "${SWIFT_FLAGS[@]}")"
    plutil -insert NextMeetingBuildIdentifier -string "$BUILD_IDENTIFIER" "$APP_DIR/Contents/Info.plist"
fi
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
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
