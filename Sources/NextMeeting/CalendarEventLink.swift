import Foundation

/// Apple Calendar's native event route uses the local calendar item identifier,
/// not the eventIdentifier or the server's external UID. Its occurrence prefix
/// is an iCalendar UTC date. Calendar opens the event inspector with options=more.
///
/// The same route is used by Raycast's native EventKit bridge:
/// https://github.com/raycast/extensions/blob/main/extensions/menubar-calendar/swift/AppleReminders/Sources/Calendar.swift
/// Calendar's installed ekevent handler passes this path to its EventKit reader.
enum CalendarEventLink {
    static func url(for meeting: Meeting) -> URL? {
        guard let identifier = meeting.calendarItemIdentifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let escapedIdentifier = identifier.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            return nil
        }

        var occurrencePrefix = ""
        if meeting.hasRecurrenceRules || meeting.occurrenceDate != nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            // A moved, detached occurrence keeps its original occurrenceDate.
            // Using the moved startDate would address a different series slot.
            let occurrence = meeting.occurrenceDate ?? meeting.startDate
            occurrencePrefix = formatter.string(from: occurrence) + "/"
        }

        var components = URLComponents()
        components.scheme = "ical"
        components.host = "ekevent"
        components.percentEncodedPath = "/" + occurrencePrefix + escapedIdentifier
        components.queryItems = [
            URLQueryItem(name: "method", value: "show"),
            URLQueryItem(name: "options", value: "more"),
        ]
        return components.url
    }

    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}
