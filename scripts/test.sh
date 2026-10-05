#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
mkdir -p "$BUILD_DIR/module-cache"

# Run the pure meeting logic without requesting calendar access or launching UI.
xcrun swiftc -parse-as-library -swift-version 6 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -target "$ARCH-apple-macosx14.0" -sdk "$SDK_PATH" \
    "$PROJECT_DIR/Sources/NextMeeting/Meeting.swift" \
    "$PROJECT_DIR/Tests/MeetingLogicTests.swift" \
    -o "$BUILD_DIR/MeetingLogicTests"
"$BUILD_DIR/MeetingLogicTests"

xcrun swiftc -parse-as-library -swift-version 6 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -target "$ARCH-apple-macosx14.0" -sdk "$SDK_PATH" \
    "$PROJECT_DIR/Sources/NextMeeting/Meeting.swift" \
    "$PROJECT_DIR/Sources/NextMeeting/CalendarEventLink.swift" \
    "$PROJECT_DIR/Tests/CalendarEventLinkTests.swift" \
    -o "$BUILD_DIR/CalendarEventLinkTests"
"$BUILD_DIR/CalendarEventLinkTests"
