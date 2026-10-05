#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIO="${1:-agenda}"
case "$SCENARIO" in agenda|empty|denied|light|popover) ;; *) echo 'Choose agenda, empty, denied, light, or popover.' >&2; exit 1;; esac
APP_DIR="$PROJECT_DIR/build/qa/NextMeeting-$SCENARIO.app"
INFO="$APP_DIR/Contents/Info.plist"
IDENTIFIER="systems.surfaces.NextMeeting.preview.$SCENARIO"
mkdir -p "$PROJECT_DIR/build/qa"
ditto "$PROJECT_DIR/build/NextMeeting.app" "$APP_DIR"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $IDENTIFIER" "$INFO"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName NextMeetingPreview' "$INFO"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName NextMeeting Preview' "$INFO"
/usr/libexec/PlistBuddy -c 'Add :NextMeetingPreview bool true' "$INFO"
/usr/libexec/PlistBuddy -c "Add :NextMeetingPreviewState string $SCENARIO" "$INFO"
if [[ "$SCENARIO" == light ]]; then
    /usr/libexec/PlistBuddy -c 'Add :NextMeetingPreviewAppearance string light' "$INFO"
fi
codesign --force --sign - --identifier "$IDENTIFIER" \
    --requirements "=designated => identifier \"$IDENTIFIER\"" \
    --entitlements "$PROJECT_DIR/Resources/NextMeeting.entitlements" "$APP_DIR"
codesign --verify --strict "$APP_DIR"
echo "Built $APP_DIR"
