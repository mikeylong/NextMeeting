import AppKit
import Combine
import EventKit
import Foundation

enum CalendarPreviewState: Sendable {
    case empty, denied
}

/// Reads calendars configured in macOS Calendar. EventKit owns account sync;
/// NextMeeting observes its changes and never saves or modifies an event.
@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var calendars: [CalendarChoice] = []
    @Published private(set) var access: CalendarAccess = .notDetermined
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private var selection: CalendarSelection

    let isDemo: Bool
    private let reader = CalendarReader()
    private let defaults: UserDefaults
    private var subscriptions = Set<AnyCancellable>()
    private var allMeetings: [Meeting] = []
    private var refreshPending = false
    private var legacySelectedIDs: Set<String>?
    private let demoAnchor: Date
    private let previewState: CalendarPreviewState?

    private static let selectionKey = "NextMeeting.calendarSelection.v2"
    private static let legacySelectionKey = "NextMeeting.selectedCalendarIDs"
    private static let legacyKnownKey = "NextMeeting.knownCalendarIDs"

    init(demo: Bool = false, previewState: CalendarPreviewState? = nil) {
        let usesDemo = demo || previewState != nil
        isDemo = usesDemo
        self.previewState = previewState
        defaults = .standard
        demoAnchor = Date()
        let stored = usesDemo ? nil : defaults.dictionary(forKey: Self.selectionKey)?.compactMapValues { $0 as? Bool }
        selection = CalendarSelection(overrides: stored ?? [:])
        if !usesDemo && stored == nil, let selected = defaults.stringArray(forKey: Self.legacySelectionKey) {
            legacySelectedIDs = Set(selected)
        }
        startObserving()
        refresh()
    }

    func requestAccess() {
        guard !isDemo, !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        Task { [weak self, reader] in
            do {
                _ = try await reader.requestAccess()
            } catch {
                self?.errorMessage = "Calendar access couldn’t be requested. Try again."
            }
            guard let self else { return }
            self.isRefreshing = false
            self.refresh()
        }
    }

    func refresh() {
        if isRefreshing {
            refreshPending = true
            return
        }
        let now = Date()
        if isDemo {
            if previewState == .denied {
                access = .denied
                calendars = []
                allMeetings = []
                meetings = []
                lastRefreshed = nil
                errorMessage = nil
                return
            }
            access = .granted
            calendars = Self.demoCalendars
            allMeetings = previewState == .empty ? [] : Self.demoMeetings(anchor: demoAnchor)
            applySelection(now: now)
            lastRefreshed = now
            errorMessage = nil
            return
        }
        access = Self.currentAccess()
        guard access == .granted else {
            allMeetings = []
            meetings = []
            calendars = []
            lastRefreshed = nil
            recordConnectionSummary()
            return
        }
        isRefreshing = true
        errorMessage = nil
        Task { [weak self, reader] in
            let snapshot = await reader.snapshot(now: now)
            guard let self else { return }
            self.access = Self.currentAccess()
            if self.access == .granted {
                self.calendars = snapshot.calendars
                self.allMeetings = snapshot.meetings
                self.migrateSelectionIfNeeded()
                self.applySelection(now: Date())
                self.lastRefreshed = Date()
            } else {
                self.calendars = []
                self.allMeetings = []
                self.meetings = []
                self.lastRefreshed = nil
            }
            self.isRefreshing = false
            self.recordConnectionSummary()
            if self.refreshPending {
                self.refreshPending = false
                self.refresh()
            }
        }
    }

    func setCalendar(id: String, enabled: Bool) {
        selection.set(id, enabled: enabled)
        if !isDemo { persistSelection() }
        applySelection(now: Date())
        recordConnectionSummary()
    }

    func isCalendarEnabled(_ id: String) -> Bool { selection.isEnabled(id) }

    func startObserving() {
        guard subscriptions.isEmpty else { return }
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &subscriptions)
        if isDemo { return }
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &subscriptions)
    }

    func stopObserving() { subscriptions.removeAll() }

    /// Counts are saved locally for the CLI check. EventKit permissions are
    /// attributed to the Launch Services app, rather than a terminal caller.
    /// No calendar names, event details, or conference URLs are recorded.
    private func recordConnectionSummary() {
        guard !isDemo else { return }
        let ready = access == .granted && lastRefreshed != nil && !isRefreshing && errorMessage == nil
        defaults.set([
            "status": ready ? "ready" : "unavailable",
            "calendarAccess": String(describing: access),
            "calendarCount": calendars.count,
            "selectedCalendarCount": calendars.filter { isCalendarEnabled($0.id) }.count,
            "meetingCount24h": meetings.count,
            "hasRefreshed": lastRefreshed != nil,
            "verifiedAt": Date().timeIntervalSince1970
        ] as [String: Any], forKey: "NextMeeting.connectionSummary")
    }

    private func applySelection(now: Date) {
        meetings = MeetingLogic.upcoming(allMeetings.filter { selection.isEnabled($0.calendarID) }, now: now)
    }

    private func migrateSelectionIfNeeded() {
        guard let selected = legacySelectedIDs else { return }
        let known = Set(defaults.stringArray(forKey: Self.legacyKnownKey) ?? calendars.map(\.id))
        selection = CalendarSelection.migrating(selectedIDs: selected, knownIDs: known)
        legacySelectedIDs = nil
        persistSelection()
    }

    private func persistSelection() {
        defaults.set(selection.overrides, forKey: Self.selectionKey)
        defaults.set(calendars.filter { selection.isEnabled($0.id) }.map(\.id), forKey: Self.legacySelectionKey)
        let known = Set(selection.overrides.keys).union(calendars.map(\.id))
        defaults.set(Array(known).sorted(), forKey: Self.legacyKnownKey)
    }

    private static func currentAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .fullAccess: return .granted
        case .writeOnly: return .writeOnly
        @unknown default: return .denied
        }
    }

    private static let demoCalendars = [
        CalendarChoice(id: "demo-work", title: "Work", source: "Example calendars", colorHex: "#4C83DA"),
        CalendarChoice(id: "demo-personal", title: "Personal", source: "Example calendars", colorHex: "#AF79D6")
    ]

    private static func demoMeetings(anchor: Date) -> [Meeting] {
        func event(_ id: String, _ title: String, minutes: Double, duration: Double, personal: Bool = false,
                   location: String? = nil, link: String? = nil, attendees: [Attendee] = []) -> Meeting {
            let calendar = demoCalendars[personal ? 1 : 0]
            return Meeting(id: id, title: title, startDate: anchor.addingTimeInterval(minutes * 60),
                           endDate: anchor.addingTimeInterval((minutes + duration) * 60), calendarTitle: calendar.title,
                           calendarID: calendar.id, colorHex: calendar.colorHex, location: location,
                           joinURL: link.flatMap(URL.init(string:)), attendees: attendees)
        }
        let reviewAttendees = [
            Attendee(id: "demo-jordan", displayName: "Jordan Lee", response: .accepted, isOrganizer: true, role: .chair),
            Attendee(id: "demo-you", displayName: "You", response: .accepted, isCurrentUser: true, role: .required),
            Attendee(id: "demo-maya", displayName: "Maya Chen", response: .accepted, role: .required),
            Attendee(id: "demo-sam", displayName: "Sam Rivera", response: .declined, role: .optional),
            Attendee(id: "demo-taylor", displayName: "Taylor Brooks", response: .noReply, role: .required),
            Attendee(id: "demo-avery", displayName: "Avery Patel", response: .tentative, role: .optional)
        ]
        let syncAttendees = reviewAttendees + [
            Attendee(id: "demo-casey", displayName: "Casey Morgan", response: .accepted),
            Attendee(id: "demo-robin", displayName: "Robin Kim", response: .accepted),
            Attendee(id: "demo-elliot", displayName: "Elliot Davis", response: .noReply),
            Attendee(id: "demo-quinn", displayName: "Quinn Williams", response: .tentative),
            Attendee(id: "demo-alex", displayName: "Alex Johnson", response: .accepted),
            Attendee(id: "demo-jamie", displayName: "Jamie Clark", response: .declined),
            Attendee(id: "demo-riley", displayName: "Riley Adams", response: .accepted),
            Attendee(id: "demo-morgan", displayName: "Morgan Wilson", response: .unknown)
        ]
        return [
            event("demo-design", "Design review", minutes: 12, duration: 45, link: "https://meet.google.com/abc-defg-hij", attendees: reviewAttendees),
            event("demo-sync", "Product sync", minutes: 95, duration: 30, link: "https://example.zoom.us/j/123456789", attendees: syncAttendees),
            event("demo-one-on-one", "Coffee with Alex", minutes: 235, duration: 45, personal: true, location: "Blue Bottle Coffee"),
            event("demo-planning", "Weekly planning", minutes: 21 * 60, duration: 30, link: "https://meet.google.com/klm-nopq-rst")
        ]
    }
}

/// The EventKit query runs off the main actor. Only value snapshots cross back
/// to SwiftUI, keeping EventKit objects inside their own isolated reader.
private actor CalendarReader {
    private lazy var store = EKEventStore()

    struct Snapshot: Sendable {
        let calendars: [CalendarChoice]
        let meetings: [Meeting]
    }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func snapshot(now: Date) -> Snapshot {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return Snapshot(calendars: [], meetings: [])
        }
        let calendars = store.calendars(for: .event)
        let choices = calendars.map { calendar in
            CalendarChoice(id: calendar.calendarIdentifier, title: calendar.title,
                           source: calendar.source.title, colorHex: Self.hex(calendar.cgColor))
        }.sorted {
            if $0.source != $1.source { return $0.source.localizedStandardCompare($1.source) == .orderedAscending }
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.id < $1.id
        }
        // An empty calendar array can mean "all calendars" in EventKit; return
        // explicitly instead of inadvertently widening the query.
        guard !calendars.isEmpty else { return Snapshot(calendars: choices, meetings: []) }
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(24 * 60 * 60), calendars: calendars)
        let events = store.events(matching: predicate)
        let meetings = events.compactMap { event -> Meeting? in
            guard event.status != .canceled,
                  !(event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) ?? false),
                  let start = event.startDate, let end = event.endDate,
                  let calendar = event.calendar else { return nil }
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawLocation = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            let join = MeetingLogic.joinURL(from: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 })
            let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
            let occurrence = event.occurrenceDate ?? start
            let id = calendar.calendarIdentifier + "|" + identifier + "|" + String(Int64(occurrence.timeIntervalSince1970 * 1_000))
            let attendees = Self.attendees(event, fallbackPrefix: id)
            return Meeting(id: id, title: title?.isEmpty == false ? title! : "Untitled meeting", startDate: start, endDate: end,
                           calendarTitle: calendar.title, calendarID: calendar.calendarIdentifier,
                           colorHex: Self.hex(calendar.cgColor), location: rawLocation?.isEmpty == false ? rawLocation : nil,
                           joinURL: join, eventIdentifier: event.eventIdentifier,
                           calendarItemIdentifier: event.calendarItemIdentifier,
                           calendarItemExternalIdentifier: event.calendarItemExternalIdentifier,
                           occurrenceDate: event.occurrenceDate, hasRecurrenceRules: event.hasRecurrenceRules,
                           isAllDay: event.isAllDay, attendees: attendees)
        }
        return Snapshot(calendars: choices, meetings: MeetingLogic.upcoming(meetings, now: now))
    }

    private static func attendees(_ event: EKEvent, fallbackPrefix: String) -> [Attendee] {
        func snapshot(_ participant: EKParticipant, fallbackID: String, organizer: Bool = false) -> Attendee {
            AttendeeLogic.snapshot(identityURI: participant.url.absoluteString, fallbackID: fallbackID,
                                   name: participant.name,
                                   response: .fromCalendarStatus(participant.participantStatus.rawValue),
                                   isOrganizer: organizer, isCurrentUser: participant.isCurrentUser,
                                   role: .fromCalendarRole(participant.participantRole.rawValue))
        }
        var attendees: [Attendee] = []
        if let organizer = event.organizer {
            attendees.append(snapshot(organizer, fallbackID: fallbackPrefix + "|organizer", organizer: true))
        }
        for (index, participant) in (event.attendees ?? []).enumerated() {
            attendees.append(snapshot(participant, fallbackID: fallbackPrefix + "|attendee|\(index)"))
        }
        return AttendeeLogic.deduplicated(attendees)
    }

    private static func hex(_ cgColor: CGColor?) -> String {
        guard let cgColor, let color = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB) else { return "#4C83DA" }
        func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(color.redComponent), byte(color.greenComponent), byte(color.blueComponent))
    }
}
