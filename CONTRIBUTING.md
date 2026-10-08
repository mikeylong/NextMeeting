# Contributing to Next Meeting

Build and test on a Mac with Xcode command line tools and Swift 6. Check the compiler with `xcrun swiftc --version`. The app targets macOS 14 or later; the scripts build for the current Mac’s architecture. No external packages are required.

## Build and test

Run from your checkout:

```sh
./scripts/build.sh
./scripts/test.sh
```

The build creates `build/Next Meeting.app` with its icon, calendar permission metadata, sandbox entitlements, MIT license notice, and a local ad hoc signature. Use this app bundle when checking calendar permission. The published releases use Developer ID signing and are currently not notarized.

Local builds show `Version <version> (local <identifier>)` in the menu-bar right-click menu. The identifier covers the source, bundle resources and configuration, build scripts, compiler, SDK version and build, and compiler flags including architecture. Moving the checkout does not change it. Run `./scripts/test-build-identifier.sh` to check this behavior. To prepare an unlabeled release bundle, run `./scripts/build.sh --release` before Developer ID signing and release packaging. The release packager rejects bundles labeled as local builds.

`scripts/test.sh` reports separate results for meeting logic, Apple Calendar event links, and meeting app routing. The checks use synthetic data and injected openers, without reading personal calendars, launching conference apps, or joining meetings.

## Preview the interface

Build a separate sample app after building the main app:

```sh
./scripts/build-preview.sh agenda
open "build/qa/NextMeeting-agenda.app"
```

The sample app has its own bundle identifier and always uses labeled sample data. Quit an open sample app before rebuilding it so the next launch uses the new executable.

The other states are `empty`, `denied`, `light`, and `popover`. For example, `./scripts/build-preview.sh light` creates `build/qa/NextMeeting-light.app`. In the popover preview, click **Open sample popover** to inspect the native arrow and panel surface together.

Render dark, light, and meeting-detail PNGs without opening the app or reading calendars:

```sh
./scripts/render-preview.sh build/previews
```

The output directory contains `NextMeeting-preview.png`, `NextMeeting-preview-light.png`, and `NextMeeting-attendees.png`. Omitting the directory writes the same filenames to `Design`; use `build/previews` for review images that should stay out of Git.

## Check a calendar connection

Quit any running copy of Next Meeting, then launch the local app bundle without preview mode and connect calendars before checking its local summary:

```sh
open "build/Next Meeting.app"
"build/Next Meeting.app/Contents/MacOS/NextMeeting" --verify-calendars
```

`--verify-calendars` reports permission status, counts, and the last verification time, without event details. Exit code 0 means the launched app refreshed successfully within the last three minutes. The diagnostic reads a saved summary because macOS can attribute calendar access differently to a terminal process.

`--inspect` opens a standard window with real calendar data for local diagnostics. Use sample previews for shared screenshots and issue reports.

## Submit a change

1. Keep the pull request focused on one behavior or fix. Explain what changed and include the validation commands you ran.
2. Run the build and tests before submitting. For interface changes, review dark and light sample previews and include images that show the changed behavior.
3. Keep fixtures, screenshots, logs, and issue reports free of real calendar details, attendee information, invitation links, and credentials. Include the app version, macOS version, and a synthetic example when reporting a problem.

To keep your commit email private, use your [GitHub noreply address](https://docs.github.com/en/account-and-profile/how-tos/email-preferences/setting-your-commit-email-address). This setting applies to future commits.

Next Meeting is [MIT licensed](LICENSE).
