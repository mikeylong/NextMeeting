# Contributing to Next Meeting

Build and test on a Mac with Xcode 26 or later command line tools, Swift 6, and the macOS 26 or later SDK. Check the compiler with `xcrun swiftc --version` and the SDK with `xcrun --sdk macosx --show-sdk-version`. The app runs on macOS 14 or later; the scripts build for the current Mac’s architecture. No external packages are required.

## Build and test

Run from your checkout:

```sh
./scripts/build.sh
./scripts/test.sh
```

The build creates `build/Next Meeting.app` with its icon, calendar permission metadata, sandbox entitlements, MIT license notice, and a local ad hoc signature. Use this app bundle when checking calendar permission. The published releases use Developer ID signing and are currently not notarized.

Local builds show `Version <version> (local <identifier>)` in the menu-bar right-click menu. The identifier covers the source, bundle resources and configuration, build scripts, compiler, SDK version and build, and compiler flags including architecture. Moving the checkout does not change it. Run `./scripts/test-build-identifier.sh` to check this behavior. To prepare an unlabeled release bundle, run `./scripts/build.sh --release` before Developer ID signing and release packaging. The release packager rejects bundles labeled as local builds.

`scripts/test.sh` reports separate results for launch modes, meeting logic, Apple Calendar event links, and meeting app routing. The checks use synthetic data and injected openers, without reading personal calendars, launching conference apps, or joining meetings. Run `scripts/test-build-preview.sh` to check preview packaging and switching scenarios.

## Preview the interface

Build a separate sample app after building the main app:

```sh
./scripts/build-preview.sh agenda
open "build/qa/NextMeetingPreview.app"
```

The sample app has one stable bundle identifier and always uses labeled sample data. All scenarios replace the same `build/qa/NextMeetingPreview.app`; quit an open sample app before rebuilding it so the next launch uses the new executable. Previews use a standard window and never create a menu bar item or an additional menu bar toggle in System Settings. Closing the preview window quits the preview app.

The other states are `empty`, `denied`, `light`, and `popover`. For example, `./scripts/build-preview.sh light` replaces the same preview app with the light scenario. In the popover preview, click **Open sample popover** to inspect the native arrow and panel surface together. The popover is anchored to that window's button rather than the menu bar.

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

`--inspect` opens a standard window with real calendar data for local diagnostics. `--preview` and `--demo` open a window with sample data. None of these modes creates a menu bar item; launch normally to check the actual menu bar. Use sample previews for shared screenshots and issue reports.

## Remove old preview entries from macOS

Older preview and screenshot builds created their own menu bar items, which macOS can keep listing in **System Settings → Menu Bar** after the apps quit. Updating the source prevents new preview entries but does not erase macOS's existing records.

On the affected Mac:

1. Quit the obsolete preview or screenshot apps. Keep the real **Next Meeting** app.
2. Locate each obsolete `.app` bundle, for example `build/qa/NextMeeting-agenda.app`, `NextMeeting-capture-dark.app`, or an old `NextMeetingPreview.app`. For each exact path, unregister it before moving it to the Trash:

   ```sh
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "/full/path/to/NextMeeting-agenda.app"
   ```

3. Move only those obsolete copies to the Trash. Leave `/Applications/Next Meeting.app` and the current `build/Next Meeting.app` in place.
4. Reopen System Settings. If old rows remain cached, log out and back in, then check again.

`lsregister -u` unregisters that bundle path from LaunchServices; it does not guarantee immediate removal of cached Menu Bar rows. Avoid resetting all of LaunchServices or Control Center, which would affect other apps and preferences. If an old entry persists, include its name and your macOS version in the issue report.

## Submit a change

1. Keep the pull request focused on one behavior or fix. Explain what changed and include the validation commands you ran.
2. Run the build and tests before submitting. For interface changes, review dark and light sample previews and include images that show the changed behavior.
3. Keep fixtures, screenshots, logs, and issue reports free of real calendar details, attendee information, invitation links, and credentials. Include the app version, macOS version, and a synthetic example when reporting a problem.

To keep your commit email private, use your [GitHub noreply address](https://docs.github.com/en/account-and-profile/how-tos/email-preferences/setting-your-commit-email-address). This setting applies to future commits.

Next Meeting is [MIT licensed](LICENSE).
