import AppKit
import Combine
import ServiceManagement

@MainActor
final class PanelNavigation: ObservableObject {
    @Published var showingSettings = false {
        didSet { if oldValue != showingSettings { invalidateCalendarOpen() } }
    }
    @Published var selectedMeeting: Meeting? {
        didSet { if oldValue?.id != selectedMeeting?.id { invalidateCalendarOpen() } }
    }
    @Published var calendarOpenError: String?
    private var calendarOpenRequest: UUID?

    func beginCalendarOpen() -> UUID {
        let request = UUID()
        calendarOpenRequest = request
        calendarOpenError = nil
        return request
    }

    func completeCalendarOpen(_ request: UUID, opened: Bool) {
        guard calendarOpenRequest == request else { return }
        calendarOpenRequest = nil
        calendarOpenError = opened ? nil : "Calendar couldn’t open this event. Refresh calendars and try again."
    }

    private func invalidateCalendarOpen() {
        calendarOpenRequest = nil
        calendarOpenError = nil
    }

    func reset() {
        showingSettings = false
        selectedMeeting = nil
        invalidateCalendarOpen()
    }
}

enum PanelLayout {
    static func height(meetingCount: Int, access: CalendarAccess, showingSettings: Bool, showingDetails: Bool) -> CGFloat {
        if showingSettings || showingDetails { return 520 }
        if access != .granted { return 480 }
        if meetingCount == 0 { return 365 }
        return min(520, 350 + CGFloat(meetingCount) * 54)
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var showMeetingTitle: Bool {
        didSet { UserDefaults.standard.set(showMeetingTitle, forKey: "showMeetingTitle") }
    }
    @Published private(set) var launchesAtLogin = false
    @Published var loginError: String?

    init() {
        showMeetingTitle = UserDefaults.standard.object(forKey: "showMeetingTitle") as? Bool ?? true
        updateLoginStatus()
    }

    func updateLoginStatus() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            updateLoginStatus()
            loginError = SMAppService.mainApp.status == .requiresApproval
                ? "Allow Next Meeting in System Settings → General → Login Items." : nil
        } catch {
            updateLoginStatus()
            loginError = "macOS couldn’t update login items. Open System Settings → General → Login Items."
        }
    }
}

enum AppActions {
    @MainActor
    static func joinMeeting(_ url: URL) async -> MeetingOpenResult {
        await MeetingLinkRouter.open(url, using: WorkspaceMeetingLinkOpener())
    }

    static func openCalendar() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    /// Dispatch the event link to Apple Calendar specifically. A successful
    /// return means Calendar accepted the open request; its UI owns selection.
    /// Never substitute a generic app launch when the event cannot be addressed.
    @MainActor
    static func openCalendar(meeting: Meeting) async -> Bool {
        guard let url = CalendarEventLink.url(for: meeting),
              let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else {
            return false
        }
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openCalendarAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
