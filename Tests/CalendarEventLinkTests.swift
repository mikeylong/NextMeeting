import Foundation

@main
struct CalendarEventLinkTests {
    static func main() {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            assertions += 1
            guard condition() else { fatalError("Failed: \(description)") }
        }
        let original = Date(timeIntervalSince1970: 1_791_171_000) // 2026-10-05 03:30:00 UTC
        let moved = original.addingTimeInterval(2 * 60 * 60)
        func meeting(itemID: String? = "LOCAL-ITEM-ID", recurring: Bool = false, occurrence: Date? = nil) -> Meeting {
            Meeting(id: "display-identity", title: "Example meeting", startDate: moved,
                    endDate: moved.addingTimeInterval(1800), calendarTitle: "Example", calendarID: "CALENDAR-ID",
                    colorHex: "#0088CC", eventIdentifier: "EVENT-ID", calendarItemIdentifier: itemID,
                    calendarItemExternalIdentifier: "SERVER-UID", occurrenceDate: occurrence,
                    hasRecurrenceRules: recurring)
        }
        let single = CalendarEventLink.url(for: meeting())!
        check(single.absoluteString == "ical://ekevent/LOCAL-ITEM-ID?method=show&options=more", "single event addresses local calendar item and opens inspector")
        check(single.host == "ekevent" && single.scheme == "ical", "uses native macOS Calendar route")
        check(!single.absoluteString.contains("EVENT-ID") && !single.absoluteString.contains("SERVER-UID"), "does not substitute incompatible event or external identifier")
        check(CalendarEventLink.url(for: meeting(itemID: nil)) == nil, "missing local identifier fails instead of launching generic Calendar")
        check(CalendarEventLink.url(for: meeting(itemID: " \n ")) == nil, "empty identifier fails")

        let recurring = CalendarEventLink.url(for: meeting(recurring: true))!
        check(recurring.absoluteString == "ical://ekevent/20261005T053000Z/LOCAL-ITEM-ID?method=show&options=more", "recurring event uses UTC occurrence start")
        let detached = CalendarEventLink.url(for: meeting(occurrence: original))!
        check(detached.absoluteString == "ical://ekevent/20261005T033000Z/LOCAL-ITEM-ID?method=show&options=more", "detached event uses original scheduled occurrence instead of moved start")
        check(CalendarEventLink.url(for: meeting(recurring: true, occurrence: original)) == detached, "original occurrence takes precedence for recurring series")

        let escaped = CalendarEventLink.url(for: meeting(itemID: "opaque/id?x=1#fragment"))!
        check(escaped.absoluteString == "ical://ekevent/opaque%2Fid%3Fx%3D1%23fragment?method=show&options=more", "opaque identifiers cannot inject paths, queries, or fragments")
        check(escaped.fragment == nil && URLComponents(url: escaped, resolvingAgainstBaseURL: false)?.queryItems?.count == 2, "only supported inspector query parameters are emitted")
        print("Calendar event links: \(assertions) checks passed.")
    }
}
