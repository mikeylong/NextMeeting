#!/bin/bash
set -euo pipefail

# Package the app that has already passed validation. This script never rebuilds
# or re-signs it, so release bytes stay tied to the reviewed application bundle.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$PROJECT_DIR/build/Next Meeting.app}"
RELEASE_DIR="$PROJECT_DIR/build/releases"
ARCH="arm64"
CHECKSUM_NAME="SHA256SUMS"

fail() { echo "Release packaging failed: $*" >&2; exit 1; }
[[ $# -le 1 ]] || fail "Usage: scripts/package-release.sh [path-to/Next Meeting.app]"
[[ -d "$APP_DIR" && ! -L "$APP_DIR" ]] || fail "Application bundle not found: $APP_DIR"
[[ "$(basename "$APP_DIR")" == "Next Meeting.app" ]] || fail "Use the canonical Next Meeting.app bundle."
APP_DIR="$(cd "$APP_DIR" && pwd)"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
EXECUTABLE="$APP_DIR/Contents/MacOS/NextMeeting"
[[ -f "$INFO_PLIST" && -x "$EXECUTABLE" ]] || fail "The app bundle is incomplete."
[[ -f "$APP_DIR/Contents/Resources/LICENSE" ]] || fail "The app bundle is missing the MIT license notice."
cmp -s "$PROJECT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE" || fail "The app's license notice does not match this source checkout."

plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST" 2>/dev/null; }
VERSION="$(plist_value CFBundleShortVersionString)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Expected a numeric major.minor.patch version."
ASSET_NAME="NextMeeting-$VERSION-macos-$ARCH.zip"
[[ "$(plist_value CFBundleIdentifier)" == "systems.surfaces.NextMeeting" ]] || fail "Unexpected bundle identifier."
[[ "$(plist_value CFBundleExecutable)" == "NextMeeting" ]] || fail "Unexpected executable."
[[ "$(plist_value CFBundleVersion)" =~ ^[1-9][0-9]*$ ]] || fail "Expected a positive build number."
[[ "$(plist_value CFBundleName)" == "Next Meeting" ]] || fail "Unexpected app name."
[[ "$(plist_value CFBundleDisplayName)" == "Next Meeting" ]] || fail "Unexpected display name."
[[ "$(plist_value LSMinimumSystemVersion)" == "14.0" ]] || fail "Expected macOS 14 minimum."
[[ "$(plist_value LSUIElement)" == "true" ]] || fail "The app must run in the menu bar."
if /usr/libexec/PlistBuddy -c 'Print :NextMeetingBuildIdentifier' "$INFO_PLIST" >/dev/null 2>&1; then
    fail "The app is labeled as a local build. Use scripts/build.sh --release to prepare a release bundle."
fi

# Diagnostic modes remain opt-in command-line features. Preview/inspection
# bundle flags must never silently turn the release into a diagnostic app.
if plutil -p "$INFO_PLIST" | /usr/bin/grep -Ei '"NextMeeting[^"]*(Preview|Inspect|Demo|Sample|Light)[^"]*"' >/dev/null; then
    fail "The app has a preview or inspection bundle flag. Rebuild the canonical app."
fi
[[ "$(lipo -archs "$EXECUTABLE")" == "$ARCH" ]] || fail "Expected an Apple silicon arm64 executable."
# Consume every load command so pipefail cannot mistake an early awk exit for
# an otool failure when the executable has more data after LC_BUILD_VERSION.
MIN_OS="$(otool -l "$EXECUTABLE" | awk '/LC_BUILD_VERSION/ { in_build = 1; next } in_build && /minos/ && !found { print $2; found = 1 }')"
[[ "$MIN_OS" == "14.0" ]] || fail "The executable must target macOS 14.0."
codesign --verify --strict --verbose=2 "$APP_DIR"

# Only the signed app belongs in the archive. Reject caches, verification
# summaries, calendar exports, logs, or any other unexpected bundle payload.
if [[ -n "$(find "$APP_DIR" -type l -print -quit)" ]]; then
    fail "Unexpected symbolic link inside the application bundle."
fi
while IFS= read -r -d '' file; do
    relative="${file#"$APP_DIR/"}"
    case "$relative" in
        Contents/Info.plist|Contents/PkgInfo|Contents/MacOS/NextMeeting|Contents/Resources/AppIcon.icns|Contents/Resources/LICENSE|Contents/_CodeSignature/CodeResources) ;;
        *) fail "Unexpected file in the app bundle: $relative" ;;
    esac
done < <(find "$APP_DIR" -type f -print0)

mkdir -p "$RELEASE_DIR"
STAGING_DIR="$(mktemp -d "$RELEASE_DIR/.package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

codesign --display --entitlements - --xml "$APP_DIR" > "$STAGING_DIR/entitlements.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$STAGING_DIR/entitlements.plist")" == "true" ]] || fail "Missing app sandbox entitlement."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.personal-information.calendars' "$STAGING_DIR/entitlements.plist")" == "true" ]] || fail "Missing calendar entitlement."

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$STAGING_DIR/$ASSET_NAME"
mkdir "$STAGING_DIR/verify"
ditto -x -k "$STAGING_DIR/$ASSET_NAME" "$STAGING_DIR/verify"
UNPACKED_APP="$STAGING_DIR/verify/Next Meeting.app"
codesign --verify --strict --verbose=2 "$UNPACKED_APP"
while IFS= read -r -d '' file; do
    relative="${file#"$APP_DIR/"}"
    cmp -s "$file" "$UNPACKED_APP/$relative" || fail "Archive round-trip changed $relative."
done < <(find "$APP_DIR" -type f -print0)

(cd "$STAGING_DIR" && shasum -a 256 "$ASSET_NAME" > "$CHECKSUM_NAME")
mv -f "$STAGING_DIR/$ASSET_NAME" "$RELEASE_DIR/$ASSET_NAME"
mv -f "$STAGING_DIR/$CHECKSUM_NAME" "$RELEASE_DIR/$CHECKSUM_NAME"
(cd "$RELEASE_DIR" && shasum -a 256 -c "$CHECKSUM_NAME")
echo "Release archive: $RELEASE_DIR/$ASSET_NAME"
echo "SHA-256 checksum: $RELEASE_DIR/$CHECKSUM_NAME"
