# NextMeeting

NextMeeting shows your next meeting in the macOS menu bar. Click it to see meetings in the next 24 hours, choose calendars, or open a meeting link.

The panel follows the macOS Weather and Display menu bar panels: a flat surface, consistent system typography, thin dividers, and a compact layout.

The native macOS popover draws the panel background and arrow as one surface. The content does not add a separate full-panel background.

## Start the app

1. Download the app ZIP from the [latest release](https://github.com/mikeylong/NextMeeting/releases/latest), unzip it, and move NextMeeting to Applications.
2. Open NextMeeting.
3. Click **Connect calendars** and allow calendar access in the macOS prompt.
4. Open **Settings** in NextMeeting and choose the calendars you want to see.

The release supports Apple silicon Macs running macOS 14 or later. To run a local build, open `build/NextMeeting.app` after using the build commands below.

NextMeeting uses calendars already connected to Apple Calendar. iCloud, Google, Exchange, and other accounts work when their events appear in Apple Calendar. To add an account, use **Manage calendar accounts** in NextMeeting’s settings and enable Calendars for the account.

If you previously denied access, go to **System Settings → Privacy & Security → Calendars** and enable NextMeeting.

## What it shows

1. The menu bar shows the next meeting’s title and a countdown. Turn off **Show meeting title in menu bar** for a shorter label.
2. The panel shows the next meeting, followed by timed events over a rolling 24 hours. Meetings already in progress are included. Ended events, all-day events, canceled meetings, and declined invitations are hidden.
3. Click any row to see meeting details and attendees. Response labels show Accepted, Declined, No reply, Tentative, or the status supplied by the calendar. Organizer, your own entry, and optional attendees are marked. Unknown stays Unknown when the calendar does not supply a response.
4. **Join meeting** opens recognized Zoom, Google Meet, Microsoft Teams, or Webex links in your default browser or meeting app. **Open Calendar** selects the meeting and opens its details in Apple Calendar, including the correct occurrence of a recurring meeting. The footer and More menu open the selected meeting, or the next meeting from the agenda.
5. Calendar changes update automatically. NextMeeting also refreshes every minute and when the Mac wakes. **Refresh Calendars** rereads Apple Calendar’s current data; Apple Calendar handles account sync.
6. **Open at login** is optional and off by default. The **More options** menu includes Quit. Right-click the menu bar item for quick actions.

Calendar selections persist. New calendars appear automatically and can be turned off individually. Times follow the Mac’s time zone, locale, and 12/24-hour preference.

NextMeeting reads events locally, never edits them, and has no account, analytics, or server. macOS requires EventKit’s full calendar-access permission to read event details; the app does not use its write capability.

## Build and verify

Requires macOS 14 or later and the Xcode command line tools. The build targets the current Mac’s architecture and has no external dependencies.

```sh
cd /Users/mike/NextMeeting
./scripts/build.sh
./scripts/test.sh
```

After launching the app and connecting calendars, check its local connection summary:

```sh
build/NextMeeting.app/Contents/MacOS/NextMeeting --verify-calendars
```

The summary contains permission status, counts, and the last verification time. It reads the app’s saved summary because macOS attributes calendar access differently to an app launched from the menu bar and a command launched from a terminal. Exit code 0 means the app refreshed successfully within the last three minutes. No event details are printed.

The build produces `build/NextMeeting.app` with a local ad hoc signature and calendar sandbox entitlement. A distributable release would need Developer ID signing and notarization.

`scripts/test.sh` checks meeting ordering, rolling-window boundaries, ongoing events, recurrence identities, calendar selection, countdowns, conference URL extraction, attendee status mapping and identity handling, and Calendar event links without reading personal calendars.

For UI review with isolated sample calendars:

```sh
build/NextMeeting.app/Contents/MacOS/NextMeeting --preview
build/NextMeeting.app/Contents/MacOS/NextMeeting --preview --preview-empty
build/NextMeeting.app/Contents/MacOS/NextMeeting --preview --preview-denied
build/NextMeeting.app/Contents/MacOS/NextMeeting --preview --light
```

Preview mode is labeled and never reads real events or opens sample meeting links. The normal app starts without preview mode.

For local UI diagnostics, `--inspect` displays the app in a standard window with live calendar data instead of samples. Launch through the app bundle when verifying calendar permission. This mode is off in the normal build.

`./scripts/build-preview.sh agenda` creates a separate sample app for UI inspection. Use `empty`, `denied`, or `light` for the other states. Use `popover` and click **Open sample popover** to inspect the native arrow and panel surface together. `./scripts/render-preview.sh` saves dark and light sample images in `Design` without capturing the screen or reading personal calendars.

Apple’s [EventKit access documentation](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) describes the calendar permission and sandbox requirements.
