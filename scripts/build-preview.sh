#!/bin/bash
set -euo pipefail

[[ $# -le 1 ]] || { echo 'Usage: scripts/build-preview.sh [agenda|empty|denied|light|popover]' >&2; exit 1; }
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIO="${1:-agenda}"
case "$SCENARIO" in agenda|empty|denied|light|popover) ;; *) echo 'Choose agenda, empty, denied, light, or popover.' >&2; exit 1;; esac
SOURCE_APP="$PROJECT_DIR/build/Next Meeting.app"
APP_DIR="$PROJECT_DIR/build/qa/NextMeetingPreview.app"
IDENTIFIER="systems.surfaces.NextMeeting.preview"
[[ -f "$SOURCE_APP/Contents/Info.plist" && -x "$SOURCE_APP/Contents/MacOS/NextMeeting" ]] || {
    echo 'Build the main app with scripts/build.sh before building a preview.' >&2
    exit 1
}
[[ ! -L "$APP_DIR" ]] || { echo "Refusing to replace a symbolic link: $APP_DIR" >&2; exit 1; }
mkdir -p "$PROJECT_DIR/build/qa"
# Build from a fresh copy so switching scenarios never retains an old flag or
# payload. All scenarios reuse one identity and path instead of registering a
# separate application with macOS for each screenshot.
STAGING_DIR="$(mktemp -d "$PROJECT_DIR/build/qa/.preview.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/NextMeetingPreview.app"
ditto "$SOURCE_APP" "$STAGED_APP"
INFO="$STAGED_APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$IDENTIFIER" "$INFO"
plutil -replace CFBundleName -string NextMeetingPreview "$INFO"
plutil -replace CFBundleDisplayName -string 'Next Meeting Preview' "$INFO"
plutil -replace LSUIElement -bool false "$INFO"
plutil -replace NextMeetingPreview -bool true "$INFO"
plutil -replace NextMeetingPreviewState -string "$SCENARIO" "$INFO"
if [[ "$SCENARIO" == light ]]; then
    plutil -replace NextMeetingPreviewAppearance -string light "$INFO"
fi
codesign --force --sign - --identifier "$IDENTIFIER" \
    --requirements "=designated => identifier \"$IDENTIFIER\"" \
    --entitlements "$PROJECT_DIR/Resources/NextMeeting.entitlements" "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
rm -rf "$APP_DIR"
mv "$STAGED_APP" "$APP_DIR"
echo "Built $APP_DIR"
