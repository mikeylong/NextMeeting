#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
mkdir -p "$BUILD_DIR/module-cache" "$PROJECT_DIR/Design"
xcrun swiftc -O -parse-as-library -swift-version 6 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -target "$(uname -m)-apple-macosx14.0" \
    "$PROJECT_DIR/Sources/NextMeeting/Meeting.swift" \
    "$PROJECT_DIR/Sources/NextMeeting/CalendarStore.swift" \
    "$PROJECT_DIR/Sources/NextMeeting/AppPreferences.swift" \
    "$PROJECT_DIR/Sources/NextMeeting/CalendarEventLink.swift" \
    "$PROJECT_DIR/Sources/NextMeeting/MeetingPanel.swift" \
    "$PROJECT_DIR/Sources/NextMeeting/PreviewSurface.swift" \
    "$PROJECT_DIR/scripts/render-preview.swift" \
    -o "$BUILD_DIR/RenderPreview"
"$BUILD_DIR/RenderPreview" "$PROJECT_DIR/Design/NextMeeting-preview.png"
"$BUILD_DIR/RenderPreview" "$PROJECT_DIR/Design/NextMeeting-preview-light.png" --light
"$BUILD_DIR/RenderPreview" "$PROJECT_DIR/Design/NextMeeting-attendees.png" --details
