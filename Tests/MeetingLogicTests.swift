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

        print("Meeting logic: \(assertions) checks passed.")
    }
}
