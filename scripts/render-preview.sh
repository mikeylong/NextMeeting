#!/bin/bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [output-directory]" >&2
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
OUTPUT_DIR="${1:-$PROJECT_DIR/Design}"
mkdir -p "$BUILD_DIR/module-cache" "$OUTPUT_DIR"

# RenderPreview supplies the entry point; keep every other app source in sync.
SOURCES=()
for source in "$PROJECT_DIR"/Sources/NextMeeting/*.swift; do
    if [[ -f "$source" && "${source##*/}" != "NextMeetingApp.swift" ]]; then
        SOURCES+=("$source")
    fi
done
if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "No preview sources found in Sources/NextMeeting." >&2
    exit 1
fi

xcrun swiftc -O -parse-as-library -swift-version 6 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -target "$(uname -m)-apple-macosx14.0" \
    "${SOURCES[@]}" \
    "$PROJECT_DIR/scripts/render-preview.swift" \
    -o "$BUILD_DIR/RenderPreview"
"$BUILD_DIR/RenderPreview" "$OUTPUT_DIR/NextMeeting-preview.png"
"$BUILD_DIR/RenderPreview" "$OUTPUT_DIR/NextMeeting-preview-light.png" --light
"$BUILD_DIR/RenderPreview" "$OUTPUT_DIR/NextMeeting-attendees.png" --details
