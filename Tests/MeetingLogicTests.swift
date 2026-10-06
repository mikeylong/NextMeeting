import Foundation

@main
struct MeetingLogicTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            assertions += 1
            guard condition() else { fatalError("Failed: \(description)") }
        }
        func event(_ id: String, start: Double, end: Double, allDay: Bool = false, title: String = "Meeting", calendar: String = "work") -> Meeting {
            Meeting(id: id, title: title, startDate: now.addingTimeInterval(start), endDate: now.addingTimeInterval(end),
                    calendarTitle: "Work", calendarID: calendar, colorHex: "#000000", isAllDay: allDay)
        }

        let ongoing = event("ongoing", start: -1200, end: 1200)
        let next = event("next", start: 600, end: 1800)
        let ended = event("ended", start: -3600, end: 0)
        let allDay = event("all-day", start: -7200, end: 7200, allDay: true)
        let boundary = event("boundary", start: 86400, end: 87000)
        let justInside = event("inside", start: 86399, end: 90000)
        let invalid = event("invalid", start: 300, end: 100)
        let candidates = MeetingLogic.upcoming([boundary, ended, next, allDay, justInside, ongoing, invalid], now: now)
        check(candidates.map(\.id) == ["ongoing", "next", "inside"], "rolling 24 hours includes ongoing and excludes invalid, ended, all-day, and exact boundary")
        check(MeetingLogic.upcoming([next], now: now, horizon: 0).isEmpty, "zero horizon has no meetings")
        check(MeetingLogic.upcoming([next], now: now, horizon: -1).isEmpty, "negative horizon has no meetings")
        check(MeetingLogic.nextMeeting([next, ongoing], now: now)?.id == "ongoing", "ongoing meeting takes precedence")
        check(MeetingLogic.nextMeeting([ended, next], now: now)?.id == "next", "ended meeting does not take precedence")
        check(MeetingLogic.nextMeeting([ended], now: now) == nil, "empty schedule has no next meeting")
        check(MeetingLogic.menuBarMeeting([ongoing, next], now: now)?.id == "next", "menu bar prioritizes an upcoming meeting that overlaps an active meeting")
        let backToBack = event("back-to-back", start: 1200, end: 2400)
        check(MeetingLogic.menuBarMeeting([backToBack, ongoing], now: now)?.id == "ongoing", "menu bar retains an active meeting when a back-to-back meeting is 20 minutes away")
        check(MeetingLogic.menuBarMeeting([backToBack, ongoing], now: now.addingTimeInterval(300))?.id == "back-to-back", "menu bar switches to the back-to-back meeting 15 minutes before it starts")
        let afterGap = event("after-gap", start: 3600, end: 5400)
        check(MeetingLogic.menuBarMeeting([ongoing, afterGap], now: now)?.id == "ongoing", "menu bar retains an active meeting when the next start is an hour away")
        check(MeetingLogic.menuBarMeeting([afterGap], now: now)?.id == "after-gap", "without an active meeting the menu bar shows the next start even beyond 15 minutes")
        let atNoticeBoundary = event("at-notice-boundary", start: 900, end: 1800)
        let beforeNoticeWindow = event("before-notice-window", start: 901, end: 1800)
        let insideNoticeWindow = event("inside-notice-window", start: 899, end: 1800)
        check(MeetingLogic.menuBarMeeting([ongoing, atNoticeBoundary], now: now)?.id == "at-notice-boundary", "the exact 15 minute boundary is included")
        check(MeetingLogic.menuBarMeeting([ongoing, beforeNoticeWindow], now: now)?.id == "ongoing", "a start 15 minutes and one second away keeps the active meeting")
        check(MeetingLogic.menuBarMeeting([ongoing, insideNoticeWindow], now: now)?.id == "inside-notice-window", "a start just inside the 15 minute window replaces the active meeting")
        check(MeetingLogic.menuBarMeeting([ongoing, beforeNoticeWindow], now: now.addingTimeInterval(1))?.id == "before-notice-window", "the menu bar advances as time enters the notice window")
        check(MeetingLogic.statusText(for: atNoticeBoundary, now: now) == "In 15 min", "the selected meeting displays a 15 minute countdown at the boundary")
        check(MeetingLogic.menuBarMeeting([ended, afterGap], now: now)?.id == "after-gap", "an ended meeting does not restrict a future start to the notice window")
        check(MeetingLogic.menuBarMeeting([afterGap, ongoing, next], now: now)?.id == "next", "menu bar selects the earliest upcoming meeting regardless of input order")
        check(MeetingLogic.menuBarMeeting([ongoing], now: now)?.id == "ongoing", "menu bar falls back to the active meeting without an upcoming meeting")
        let startingNow = event("starting-now", start: 0, end: 1800)
        check(MeetingLogic.menuBarMeeting([startingNow, next], now: now)?.id == "next", "a meeting starting now is active so the menu bar advances to the next meeting")
        check(MeetingLogic.menuBarMeeting([startingNow], now: now)?.id == "starting-now", "a meeting starting now remains visible without an upcoming meeting")
        check(MeetingLogic.menuBarMeeting([ended, allDay, invalid, boundary, ongoing], now: now)?.id == "ongoing", "ineligible events and the exact 24 hour boundary do not replace the active meeting")
        check(MeetingLogic.menuBarMeeting([ended, allDay, invalid, boundary], now: now) == nil, "menu bar has no meeting when the rolling schedule is empty")
        check(MeetingLogic.menuBarMeeting([next], now: now)?.id == "next", "menu bar shows the upcoming meeting without an active meeting")
        check(MeetingLogic.menuBarMeeting([ongoing, next], now: next.startDate)?.id == "ongoing", "when the upcoming meeting starts and no future meeting remains the menu bar returns to active meeting ordering")
        check(MeetingLogic.upcoming([next, next], now: now).count == 1, "exact identity duplicates are removed")
        check(MeetingLogic.upcoming([next, event("next-occurrence", start: 7200, end: 8000)], now: now).count == 2, "separate recurring occurrences remain")
        check(MeetingLogic.upcoming([next, event("other-calendar", start: 600, end: 1800, calendar: "personal")], now: now).count == 2, "separate calendar identities remain")
        let simultaneous = [event("b", start: 600, end: 1800, title: "Beta"), event("a", start: 600, end: 1800, title: "Alpha")]
        check(MeetingLogic.upcoming(simultaneous, now: now).map(\.id) == ["a", "b"], "ties sort deterministically")
        check(MeetingLogic.statusText(for: ongoing, now: now) == "Now", "ongoing status")
        check(MeetingLogic.statusText(for: next, now: now) == "In 10 min", "minute countdown")
        check(MeetingLogic.statusText(for: event("soon", start: 1, end: 20), now: now) == "In 1 min", "countdown rounds up")
        check(MeetingLogic.statusText(for: event("hour", start: 3600, end: 4000), now: now) == "In 1 hr", "exact hour countdown")
        check(MeetingLogic.statusText(for: event("later", start: 7500, end: 8000), now: now) == "In 2 hr 5 min", "hour and minute countdown")
        check(MeetingLogic.statusText(for: ended, now: now) == "Ended", "ended status")

        func namedCalendar(_ title: String, source: String = "") -> Meeting {
            Meeting(id: "calendar-label", title: "Meeting", startDate: now, endDate: now.addingTimeInterval(1800),
                    calendarTitle: title, calendarSource: source, calendarID: "work", colorHex: "#000000")
        }
        let organizationCalendar = namedCalendar("Calendar", source: "Example organization")
        check(organizationCalendar.calendarDisplayTitle == "Example organization · Calendar", "generic calendar name includes its actual source")
        check(namedCalendar("  Calendar \n", source: "  Example organization \n").calendarDisplayTitle == "Example organization · Calendar", "calendar display trims source and title whitespace")
        check(namedCalendar("Work").calendarDisplayTitle == "Work", "older meeting snapshots retain their calendar title without a source")
        check(namedCalendar("Work", source: " \n").calendarDisplayTitle == "Work", "blank source does not add a separator")
        check(namedCalendar("Work", source: "work").calendarDisplayTitle == "Work", "equivalent source and calendar titles appear once")
        check(namedCalendar(" \n", source: "Example organization").calendarDisplayTitle == "Example organization", "missing calendar title retains the known source")
        check(namedCalendar(" \n").calendarDisplayTitle == "Calendar", "missing source and title have a readable fallback")
        check(MeetingLogic.upcoming([organizationCalendar], now: now).first == organizationCalendar,
              "schedule filtering retains source, calendar title, and meeting identity")

        let links = [
            "https://company.zoom.us/j/123456789?pwd=abc",
            "https://zoom.us/my/designteam",
            "https://meet.google.com/abc-defg-hij",
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_example/0?context=abc",
            "https://teams.live.com/meet/123456789",
            "https://teams.cloud.microsoft/meet/123456789",
            "https://company.webex.com/meet/alex",
            "https://company.webex.com/company/j.php?MTID=m123"
        ]
        for link in links {
            check(MeetingLogic.joinURL(from: ["Join here: <\(link)>"])?.absoluteString == link, "recognized conference URL \(link)")
        }
        check(MeetingLogic.joinURL(from: ["Notes (https://meet.google.com/abc-defg-hij).", "https://example.com"])?.host == "meet.google.com", "embedded conference link strips punctuation")
        check(MeetingLogic.joinURL(from: ["https://company.zoom.us/j/123?pwd=abc&amp;foo=1"])?.query == "pwd=abc&foo=1", "HTML ampersands decode")
        for link in ["https://example.com/meeting", "https://zoom.us/pricing", "https://zoom.us.evil.example/j/123", "https://meet.google.com.evil.example/abc-defg-hij", "https://meet.google.com/about", "http://zoom.us/j/123", "https://user@zoom.us/j/123", "https://zoom.us:8443/j/123", "https://company.webex.com/company/j.php"] {
            check(MeetingLogic.joinURL(from: [link]) == nil, "nonconference or unsafe lookalike URL rejected")
        }
        check(MeetingLogic.joinURL(from: ["https://example.com", "https://meet.google.com/abc-defg-hij"])?.host == "meet.google.com", "scan continues after ordinary website")

        var selection = CalendarSelection()
        check(selection.isEnabled("new"), "new calendars enabled by default")
        selection.set("work", enabled: false)
        check(!selection.isEnabled("work"), "disabled calendar stays disabled")
        check(selection.isEnabled("other"), "unrelated calendar stays enabled")
        let migrated = CalendarSelection.migrating(selectedIDs: ["work", "temporarily-missing"], knownIDs: ["work", "personal"])
        check(migrated.isEnabled("work"), "migration retains selected calendar")
        check(!migrated.isEnabled("personal"), "migration retains disabled calendar")
        check(migrated.isEnabled("temporarily-missing"), "migration preserves missing selected calendar")
        check(migrated.isEnabled("brand-new"), "migration enables newly added calendar")
        let emptySelection = CalendarSelection.migrating(selectedIDs: [], knownIDs: ["work"])
        check(!emptySelection.isEnabled("work"), "explicit empty selection remains empty")

        // EventKit uses distinct values for an unknown status and no response.
        // Preserve all statuses and avoid guessing for future framework values.
        let responseCases: [AttendeeResponse] = [.unknown, .noReply, .accepted, .declined, .tentative, .delegated, .completed, .inProcess]
        for (rawValue, expected) in responseCases.enumerated() {
            check(AttendeeResponse.fromCalendarStatus(rawValue) == expected, "calendar response mapping")
        }
        check(AttendeeResponse.fromCalendarStatus(99) == .unknown, "future response remains unknown")
        check(AttendeeResponse.fromCalendarStatus(-1) == .unknown, "invalid response remains unknown")
        check(AttendeeResponse.unknown.displayText == "Unknown", "unknown attendance is not presented as no reply")
        check(AttendeeResponse.noReply.displayText == "No reply", "pending attendance has a direct reply label")
        check(AttendeeRole.fromCalendarRole(2) == .optional, "optional role is preserved")
        check(AttendeeRole.fromCalendarRole(99) == .unknown, "future role remains unknown")

        func attendee(_ uri: String?, fallback: String, name: String? = "Alex", response: AttendeeResponse = .accepted,
                      organizer: Bool = false, currentUser: Bool = false, role: AttendeeRole? = nil) -> Attendee {
            AttendeeLogic.snapshot(identityURI: uri, fallbackID: fallback, name: name, response: response,
                                   isOrganizer: organizer, isCurrentUser: currentUser, role: role)
        }
        let alex = attendee("mailto:alex@example.test", fallback: "0")
        let anotherAlex = attendee("mailto:other-alex@example.test", fallback: "1")
        check(AttendeeLogic.deduplicated([alex, anotherAlex]).count == 2, "equal display names never merge distinct people")
        check(AttendeeLogic.deduplicated([alex, alex]).count == 1, "shared stable participant URI deduplicates")
        let anonymous = [attendee(nil, fallback: "0", name: nil), attendee("", fallback: "1", name: nil), attendee("   ", fallback: "2", name: "")]
        let distinctAnonymous = AttendeeLogic.deduplicated(anonymous)
        check(distinctAnonymous.count == 3 && Set(distinctAnonymous.map(\.id)).count == 3, "missing and empty URIs preserve distinct fallback identities")
        check(distinctAnonymous.allSatisfy { $0.displayName == "Unknown" }, "missing names stay unknown")
        check(attendee("mailto:name@example.test", fallback: "0", name: "  Jordan Lee \n").displayName == "Jordan Lee", "calendar names trim whitespace")
        let addressOnly = attendee("mailto:alex%2Bcalendar%40example.test?subject=Meeting", fallback: "0", name: nil, response: .unknown)
        check(addressOnly.displayName == "alex+calendar@example.test", "unnamed mailto participant uses decoded address without URI query")
        check(addressOnly.response == .unknown, "email fallback never infers attendance")
        check(attendee("MAILTO:alex@example.test", fallback: "0", name: "   ").displayName == "alex@example.test", "blank name falls back to mailto address case-insensitively")
        check(attendee("https://calendar.example.test/participants/123", fallback: "0", name: nil).displayName == "Unknown", "nonemail URI does not become a name")
        check(attendee("mailto:", fallback: "0", name: nil).displayName == "Unknown", "empty mailto address remains unknown")
        let blankIdentity = Attendee(id: "", displayName: "Unknown", response: .unknown)
        check(Set(AttendeeLogic.deduplicated([blankIdentity, blankIdentity]).map(\.id)).count == 2, "blank caller identities do not merge anonymous people")
        let organizer = attendee("mailto:host@example.test", fallback: "organizer", name: "Host", response: .unknown, organizer: true, role: .unknown)
        let organizerInvite = attendee("mailto:host@example.test", fallback: "2", name: "Host", currentUser: true, role: .optional)
        let mergedOrganizer = AttendeeLogic.deduplicated([alex, organizerInvite, anotherAlex, organizer])
        check(mergedOrganizer.map(\.id) == [organizer.id, alex.id, anotherAlex.id], "organizer first with original attendee order preserved")
        check(mergedOrganizer.first?.isOrganizer == true && mergedOrganizer.first?.isCurrentUser == true, "organizer and current-user flags merge by identity")
        check(mergedOrganizer.first?.response == .accepted && mergedOrganizer.first?.role == .optional, "attendee details supplement unknown organizer fields")
        check(AttendeeLogic.deduplicated([organizer]).first?.response == .unknown, "organizer is retained without an inferred accepted response")
        check(AttendeeLogic.deduplicated([]).isEmpty, "missing attendees remain an empty list")
        let decline = attendee("mailto:alex@example.test", fallback: "0", response: .declined)
        check(AttendeeLogic.deduplicated([decline]).first?.response == .declined, "declined attendees are retained for details")
        check(AttendeeLogic.deduplicated([alex, decline, alex]).first?.response == .unknown, "contradictory duplicate attendance remains unknown")
        let unnamedHost = attendee("mailto:host@example.test", fallback: "0", name: nil, response: .unknown, organizer: true)
        check(AttendeeLogic.deduplicated([unnamedHost, organizerInvite]).first?.displayName == "Host", "known attendee name supplements unknown organizer name")
        check(AttendeeLogic.deduplicated([alex, anotherAlex]).map(\.id) == [alex.id, anotherAlex.id], "ordinary attendee order stays stable")

        let displayLocale = Locale(identifier: "en_US")
        let zoeHost = attendee("mailto:zoe@example.test", fallback: "host", name: "Zoe", response: .tentative,
                               organizer: true, currentUser: true, role: .chair)
        let alice = attendee("mailto:alice@example.test", fallback: "alice", name: "alice", response: .declined, role: .optional)
        let bob = attendee("mailto:bob@example.test", fallback: "bob", name: "Bob")
        let emile = attendee("mailto:emile@example.test", fallback: "emile", name: "Émile")
        let sortedAttendees = AttendeeLogic.alphabeticallySorted([zoeHost, bob, emile, alice], locale: displayLocale)
        check(sortedAttendees.map(\.displayName) == ["alice", "Bob", "Émile", "Zoe"], "visible attendee names sort alphabetically with case and locale collation")
        check(sortedAttendees.last == zoeHost, "organizer sorts alphabetically and retains Organizer, You, role, and response metadata")
        check(sortedAttendees.first == alice, "sorting retains attendee response and optional role")
        let lowerAlex = attendee("mailto:lower-alex@example.test", fallback: "lower", name: "alex")
        let equalNames = [anotherAlex, lowerAlex, alex]
        check(AttendeeLogic.alphabeticallySorted(equalNames, locale: displayLocale) == equalNames, "equivalent visible names retain distinct identities and source order")
        let fallbackNames = [anonymous[0], addressOnly, bob]
        check(AttendeeLogic.alphabeticallySorted(fallbackNames, locale: displayLocale).map(\.id) == [addressOnly.id, bob.id, anonymous[0].id], "email and Unknown fallback names follow visible alphabetical order")
        check(AttendeeLogic.alphabeticallySorted([], locale: displayLocale).isEmpty, "empty attendee list stays empty")
        check(AttendeeLogic.alphabeticallySorted([zoeHost], locale: displayLocale) == [zoeHost], "one attendee is unchanged")
        check(sortedAttendees.count == 4 && Set(sortedAttendees.map(\.id)).count == 4, "alphabetizing never drops attendees")

        print("Meeting logic: \(assertions) checks passed.")
    }
}
