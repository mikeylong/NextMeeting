import Foundation

struct Meeting: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
    let calendarID: String
    let colorHex: String
    let location: String?
    let joinURL: URL?
    let eventIdentifier: String?
    let calendarItemIdentifier: String?
    let calendarItemExternalIdentifier: String?
    let occurrenceDate: Date?
    let hasRecurrenceRules: Bool
    let isAllDay: Bool
    let attendees: [Attendee]

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        calendarTitle: String,
        calendarID: String,
        colorHex: String,
        location: String? = nil,
        joinURL: URL? = nil,
        eventIdentifier: String? = nil,
        calendarItemIdentifier: String? = nil,
        calendarItemExternalIdentifier: String? = nil,
        occurrenceDate: Date? = nil,
        hasRecurrenceRules: Bool = false,
        isAllDay: Bool = false,
        attendees: [Attendee] = []
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarTitle = calendarTitle
        self.calendarID = calendarID
        self.colorHex = colorHex
        self.location = location
        self.joinURL = joinURL
        self.eventIdentifier = eventIdentifier
        self.calendarItemIdentifier = calendarItemIdentifier
        self.calendarItemExternalIdentifier = calendarItemExternalIdentifier
        self.occurrenceDate = occurrenceDate
        self.hasRecurrenceRules = hasRecurrenceRules
        self.isAllDay = isAllDay
        self.attendees = attendees
    }

    func isOngoing(at now: Date) -> Bool {
        startDate <= now && endDate > now
    }
}

struct Attendee: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let response: AttendeeResponse
    let isOrganizer: Bool
    let isCurrentUser: Bool
    let role: AttendeeRole?

    init(id: String, displayName: String, response: AttendeeResponse, isOrganizer: Bool = false,
         isCurrentUser: Bool = false, role: AttendeeRole? = nil) {
        self.id = id
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = name.isEmpty ? "Unknown" : name
        self.response = response
        self.isOrganizer = isOrganizer
        self.isCurrentUser = isCurrentUser
        self.role = role
    }
}

/// Raw values match EventKit's documented participant status constants.
/// A missing or future status remains Unknown rather than implying no reply.
enum AttendeeResponse: Int, Equatable, Sendable {
    case unknown = 0, noReply = 1, accepted = 2, declined = 3, tentative = 4
    case delegated = 5, completed = 6, inProcess = 7

    static func fromCalendarStatus(_ rawValue: Int) -> AttendeeResponse {
        AttendeeResponse(rawValue: rawValue) ?? .unknown
    }

    var displayText: String {
        switch self {
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .noReply: return "No reply"
        case .tentative: return "Tentative"
        case .unknown: return "Unknown"
        case .delegated: return "Delegated"
        case .completed: return "Completed"
        case .inProcess: return "In progress"
        }
    }
}

enum AttendeeRole: Int, Equatable, Sendable {
    case unknown = 0, required = 1, optional = 2, chair = 3, nonParticipant = 4

    static func fromCalendarRole(_ rawValue: Int) -> AttendeeRole {
        AttendeeRole(rawValue: rawValue) ?? .unknown
    }

    var displayText: String {
        switch self {
        case .required: return "Required"
        case .optional: return "Optional"
        case .chair: return "Chair"
        case .nonParticipant: return "Non-participant"
        case .unknown: return "Unknown"
        }
    }
}

enum AttendeeLogic {
    static func snapshot(identityURI: String?, fallbackID: String, name: String?, response: AttendeeResponse,
                         isOrganizer: Bool = false, isCurrentUser: Bool = false, role: AttendeeRole? = nil) -> Attendee {
        let uri = identityURI?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let providedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = providedName.isEmpty ? emailAddress(from: uri) ?? "Unknown" : providedName
        return Attendee(id: uri.isEmpty ? "anonymous:" + fallbackID : "uri:" + uri,
                        displayName: displayName, response: response,
                        isOrganizer: isOrganizer, isCurrentUser: isCurrentUser, role: role)
    }

    /// Only a shared participant URI establishes shared identity. Names never
    /// establish identity, and anonymous entries keep distinct fallback IDs.
    static func deduplicated(_ attendees: [Attendee]) -> [Attendee] {
        var result: [Attendee] = []
        var positions: [String: Int] = [:]
        var conflictingResponses = Set<String>()
        var conflictingRoles = Set<String>()
        for (index, attendee) in attendees.enumerated() {
            let identity = attendee.id.isEmpty ? "anonymous:dedup:\(index)" : attendee.id
            guard let position = positions[identity] else {
                positions[identity] = result.count
                result.append(Attendee(id: identity, displayName: attendee.displayName, response: attendee.response,
                                       isOrganizer: attendee.isOrganizer, isCurrentUser: attendee.isCurrentUser, role: attendee.role))
                continue
            }
            let previous = result[position]
            let response: AttendeeResponse
            if conflictingResponses.contains(identity) { response = .unknown }
            else if previous.response == .unknown { response = attendee.response }
            else if attendee.response == .unknown || previous.response == attendee.response { response = previous.response }
            else {
                response = .unknown
                conflictingResponses.insert(identity)
            }
            let role: AttendeeRole?
            if conflictingRoles.contains(identity) { role = .unknown }
            else if previous.role == nil || previous.role == .unknown { role = attendee.role ?? previous.role }
            else if attendee.role == nil || attendee.role == .unknown || previous.role == attendee.role { role = previous.role }
            else {
                role = .unknown
                conflictingRoles.insert(identity)
            }
            let previousWasFallback = previous.displayName == "Unknown" || previous.displayName == emailAddress(from: String(identity.dropFirst(4)))
            result[position] = Attendee(id: identity,
                                        displayName: previousWasFallback && attendee.displayName != "Unknown" ? attendee.displayName : previous.displayName,
                                        response: response, isOrganizer: previous.isOrganizer || attendee.isOrganizer,
                                        isCurrentUser: previous.isCurrentUser || attendee.isCurrentUser, role: role)
        }
        // Stable partition: organizer first, then the calendar's attendee order.
        return result.filter(\.isOrganizer) + result.filter { !$0.isOrganizer }
    }

    private static func emailAddress(from uri: String) -> String? {
        guard let components = URLComponents(string: uri), components.scheme?.lowercased() == "mailto" else { return nil }
        let address = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address.contains("@"), address.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return address
    }
}

struct CalendarChoice: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let source: String
    let colorHex: String
}

enum CalendarAccess: Equatable, Sendable {
    case notDetermined, granted, denied, restricted, writeOnly
}

enum MeetingLogic {
    /// The rolling window includes meetings already in progress and excludes
    /// all-day events, events that have ended, and the exact horizon boundary.
    static func upcoming(_ meetings: [Meeting], now: Date, horizon: TimeInterval = 24 * 60 * 60) -> [Meeting] {
        guard horizon > 0 else { return [] }
        let windowEnd = now.addingTimeInterval(horizon)
        var seen = Set<String>()
        return meetings
            .filter { !$0.isAllDay && $0.endDate > now && $0.endDate > $0.startDate && $0.startDate < windowEnd }
            .sorted(by: precedes)
            .filter { seen.insert($0.id).inserted }
    }

    static func nextMeeting(_ meetings: [Meeting], now: Date) -> Meeting? {
        let candidates = upcoming(meetings, now: now)
        return candidates.first(where: { $0.isOngoing(at: now) }) ?? candidates.first
    }

    static func statusText(for meeting: Meeting, now: Date) -> String {
        if meeting.endDate <= now { return "Ended" }
        if meeting.isOngoing(at: now) { return "Now" }
        let minutes = max(1, Int(ceil(meeting.startDate.timeIntervalSince(now) / 60)))
        if minutes < 60 { return "In \(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "In \(hours) hr" : "In \(hours) hr \(remainder) min"
    }

    /// Only recognized conference links become a Join action. A normal event
    /// website or a URL on a lookalike domain must never be presented as one.
    static func joinURL(from fields: [String]) -> URL? {
        guard let expression = try? NSRegularExpression(pattern: "https://[^\\s<>\\\"']+", options: .caseInsensitive) else { return nil }
        for field in fields {
            let text = field.replacingOccurrences(of: "&amp;", with: "&")
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in expression.matches(in: text, range: range) {
                guard let matchedRange = Range(match.range, in: text) else { continue }
                let candidate = String(text[matchedRange]).trimmingCharacters(in: CharacterSet(charactersIn: ").,;!?]}"))
                guard let url = URL(string: candidate), isConferenceURL(url) else { continue }
                return url
            }
        }
        return nil
    }

    static func isConferenceURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        let components = path.split(separator: "/")
        func belongsTo(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if belongsTo("zoom.us") || belongsTo("zoomgov.com") {
            guard components.count >= 2 else { return false }
            if components[0] == "my" { return !components[1].isEmpty }
            if ["j", "s", "w"].contains(String(components[0])) {
                return components[1].allSatisfy(\.isNumber)
            }
            return components.count >= 3 && components[0] == "wc" && components[1] == "join" && components[2].allSatisfy(\.isNumber)
        }
        if host == "meet.google.com" {
            if components.count >= 2 && components[0] == "lookup" { return true }
            guard components.count == 1 else { return false }
            return components[0].range(of: "^[a-z]{3}-[a-z]{4}-[a-z]{3}$", options: .regularExpression) != nil
        }
        if host == "teams.microsoft.com" || host == "teams.live.com" || host == "teams.cloud.microsoft" {
            return path.hasPrefix("/l/meetup-join/") || (components.count >= 2 && components[0] == "meet")
        }
        if belongsTo("webex.com") {
            if components.count >= 2 && ["meet", "join"].contains(String(components[0])) { return true }
            if path.hasSuffix("/j.php") || path.hasSuffix("/g.php") {
                return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: {
                    $0.name.lowercased() == "mtid" && !($0.value ?? "").isEmpty
                }) == true
            }
        }
        return false
    }

    private static func precedes(_ lhs: Meeting, _ rhs: Meeting) -> Bool {
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        if lhs.calendarID != rhs.calendarID { return lhs.calendarID < rhs.calendarID }
        return lhs.id < rhs.id
    }
}

/// Overrides retain the choice for calendars that temporarily disappear during
/// an account sync. New calendars are enabled by default.
struct CalendarSelection: Equatable, Sendable {
    var overrides: [String: Bool]

    init(overrides: [String: Bool] = [:]) { self.overrides = overrides }

    func isEnabled(_ id: String) -> Bool { overrides[id] ?? true }

    mutating func set(_ id: String, enabled: Bool) { overrides[id] = enabled }

    static func migrating(selectedIDs: Set<String>, knownIDs: Set<String>) -> CalendarSelection {
        CalendarSelection(overrides: Dictionary(uniqueKeysWithValues:
            knownIDs.union(selectedIDs).map { ($0, selectedIDs.contains($0)) }
        ))
    }
}
