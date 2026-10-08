#!/bin/bash
set -euo pipefail

# Hash build inputs using relative paths, so moving the checkout does not change
# its identity. Compiler cache, SDK installation, and output paths are locations,
# not inputs; identify the SDK by its version and build instead.
[[ $# -ge 5 ]] || { echo 'Usage: build-identifier.sh project-root compiler-version sdk-version sdk-build compiler-flags...' >&2; exit 1; }
PROJECT_DIR="$1"
COMPILER_VERSION="$2"
SDK_VERSION="$3"
SDK_BUILD="$4"
shift 4

export LC_ALL=C
cd "$PROJECT_DIR"
INPUTS=(Sources/NextMeeting/*.swift Resources/Info.plist
    Resources/NextMeeting.entitlements Resources/AppIcon.icns LICENSE
    scripts/build.sh scripts/make-icon.swift scripts/build-identifier.sh)

{
    printf '%s\0' 'NextMeeting build inputs v1' 'compiler' "$COMPILER_VERSION" \
        'sdk-version' "$SDK_VERSION" 'sdk-build' "$SDK_BUILD" 'compiler-flags' "$@"
    shasum -a 256 "${INPUTS[@]}"
} | shasum -a 256 | cut -c1-10
