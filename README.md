# Next Meeting

Next Meeting shows your next meeting in the macOS menu bar. Click it to see meetings in the next 24 hours, choose calendars, or open a meeting link.

The panel follows the macOS Weather and Display menu bar panels: a flat surface, consistent system typography, thin dividers, and a compact layout.

The native macOS popover draws the panel background and arrow as one surface. The content does not add a separate full-panel background.

## Start the app

1. Download the app ZIP from the [latest release](https://github.com/mikeylong/NextMeeting/releases/latest), unzip it, and move Next Meeting to Applications.
2. Open Next Meeting.
3. Click **Connect calendars** and allow calendar access in the macOS prompt.
4. Open **Settings** in Next Meeting and choose the calendars you want to see.

The release supports Apple silicon Macs running macOS 14 or later. To run a local build, open `build/Next Meeting.app` after using the build commands below.

Next Meeting uses calendars already connected to Apple Calendar. iCloud, Google, Exchange, and other accounts work when their events appear in Apple Calendar. To add an account, use **Manage calendar accounts** in Next Meeting’s settings and enable Calendars for the account.

If you previously denied access, go to **System Settings → Privacy & Security → Calendars** and enable Next Meeting.

## What it shows

1. The menu bar shows the next meeting’s title and a countdown. Turn off **Show meeting title in menu bar** for a shorter label.
2. The panel shows the next meeting, followed by timed events over a rolling 24 hours. Meetings already in progress are included. Ended events, all-day events, canceled meetings, and declined invitations are hidden.
3. Click any row to see meeting details and attendees. Attendees are sorted alphabetically by their displayed names, including the organizer. Response labels show Accepted, Declined, No reply, Tentative, or the status supplied by the calendar. Organizer, your own entry, and optional attendees are marked. Unknown stays Unknown when the calendar does not supply a response.
4. **Join meeting** opens supported Zoom, Microsoft Teams, and Webex invitations in the matching installed app. If the app is unavailable or the native open request fails, the original invitation opens in your default browser. Google Meet opens in the browser. Zoom personal-room names and host-start invitations also use the browser because they cannot be represented faithfully by the supported native join format. **Open Calendar** selects the meeting and opens its details in Apple Calendar, including the correct occurrence of a recurring meeting. The footer and More menu open the selected meeting, or the next meeting from the agenda.
5. Calendar changes update automatically. Next Meeting also refreshes every minute and when the Mac wakes. **Refresh Calendars** rereads Apple Calendar’s current data; Apple Calendar handles account sync.
6. **Open at login** is optional and off by default. The **More options** menu includes Quit. Right-click the menu bar item for quick actions.

Calendar selections persist. New calendars appear automatically and can be turned off individually. Times follow the Mac’s time zone, locale, and 12/24-hour preference.

Meeting labels show the account name followed by the calendar name, such as **Example organization · Calendar**. Account names come from Apple Calendar. Detail icons align with the first line of text, including rows with a subtitle or a wrapped title.

Next Meeting reads events locally, never edits them, and has no account, analytics, or server. macOS requires EventKit’s full calendar-access permission to read event details; the app does not use its write capability.

## Build and contribute

Building requires macOS and Xcode command line tools with Swift 6. The app targets macOS 14 or later. The build uses the current Mac’s architecture and has no external dependencies.

```sh
git clone https://github.com/mikeylong/NextMeeting.git
cd NextMeeting
./scripts/build.sh
./scripts/test.sh
```

The build creates `build/Next Meeting.app` with a local ad hoc signature. See [CONTRIBUTING.md](CONTRIBUTING.md) for sample previews, calendar diagnostics, and pull request checks. The [meeting app routing notes](docs/meeting-app-routing.md) describe the native formats and verification limits.

Apple’s [EventKit access documentation](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) describes the calendar permission and sandbox requirements.

## License

MIT. See [LICENSE](LICENSE).
