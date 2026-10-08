#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$PROJECT_DIR/scripts/build-identifier.sh"
FIXTURE_DIR="$(mktemp -d /private/tmp/nextmeeting-identifier.XXXXXX)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT
FIRST="$FIXTURE_DIR/first checkout"
SECOND="$FIXTURE_DIR/relocated/second checkout"
INPUTS=(Sources/NextMeeting/Example.swift Resources/Info.plist
    Resources/NextMeeting.entitlements Resources/AppIcon.icns LICENSE
    scripts/build.sh scripts/make-icon.swift scripts/build-identifier.sh)

mkdir -p "$FIRST/Sources/NextMeeting" "$FIRST/Resources" "$FIRST/scripts" "$FIXTURE_DIR/relocated"
for input in "${INPUTS[@]}"; do
    printf 'Synthetic input: %s\n' "$input" > "$FIRST/$input"
done
cp -R "$FIRST" "$SECOND"

identifier() {
    "$HELPER" "$1" 'Swift compiler 6.0' '26.0' '25A123' \
        -O -swift-version 6 -target arm64-apple-macosx14.0
}
BASELINE="$(identifier "$FIRST")"
[[ "$BASELINE" =~ ^[0-9a-f]{10}$ ]] || { echo 'Invalid identifier format.' >&2; exit 1; }
[[ "$(identifier "$FIRST")" == "$BASELINE" ]] || { echo 'Identifier is not deterministic.' >&2; exit 1; }
[[ "$(identifier "$SECOND")" == "$BASELINE" ]] || { echo 'Identifier depends on checkout location.' >&2; exit 1; }

for input in "${INPUTS[@]}"; do
    printf 'Changed input\n' >> "$SECOND/$input"
    [[ "$(identifier "$SECOND")" != "$BASELINE" ]] || { echo "Identifier ignored $input." >&2; exit 1; }
    cp "$FIRST/$input" "$SECOND/$input"
done
printf 'Additional source\n' > "$SECOND/Sources/NextMeeting/Added.swift"
[[ "$(identifier "$SECOND")" != "$BASELINE" ]] || { echo 'Identifier ignored an added source.' >&2; exit 1; }
rm "$SECOND/Sources/NextMeeting/Added.swift"
mv "$SECOND/Sources/NextMeeting/Example.swift" "$SECOND/Sources/NextMeeting/Renamed.swift"
[[ "$(identifier "$SECOND")" != "$BASELINE" ]] || { echo 'Identifier ignored a renamed source.' >&2; exit 1; }
mv "$SECOND/Sources/NextMeeting/Renamed.swift" "$SECOND/Sources/NextMeeting/Example.swift"

check_metadata() {
    [[ "$("$HELPER" "$FIRST" "$@")" != "$BASELINE" ]] || { echo 'Identifier ignored changed toolchain or compiler flags.' >&2; exit 1; }
}
check_metadata 'Swift compiler 6.1' '26.0' '25A123' -O -swift-version 6 -target arm64-apple-macosx14.0
check_metadata 'Swift compiler 6.0' '26.1' '25A123' -O -swift-version 6 -target arm64-apple-macosx14.0
check_metadata 'Swift compiler 6.0' '26.0' '25B456' -O -swift-version 6 -target arm64-apple-macosx14.0
check_metadata 'Swift compiler 6.0' '26.0' '25A123' -Onone -swift-version 6 -target arm64-apple-macosx14.0
check_metadata 'Swift compiler 6.0' '26.0' '25A123' -O -swift-version 6 -target x86_64-apple-macosx14.0

rm "$SECOND/Resources/AppIcon.icns"
if identifier "$SECOND" >/dev/null 2>&1; then
    echo 'Identifier accepted a missing build input.' >&2
    exit 1
fi
echo 'Build identifier checks passed: stable across paths; tracks files, compiler, SDK, flags, and target.'
