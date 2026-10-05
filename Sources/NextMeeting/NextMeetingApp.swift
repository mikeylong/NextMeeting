import AppKit
import SwiftUI
import Combine

@main
enum NextMeetingApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        if ProcessInfo.processInfo.arguments.contains("--verify-calendars") {
            verifyCalendars()
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    /// Local verification prints counts only. It never requests permission or
    /// prints event titles, calendar names, locations, notes, or meeting URLs.
    @MainActor
    private static func verifyCalendars() {
        guard var report = UserDefaults.standard.dictionary(forKey: "NextMeeting.connectionSummary"),
              let verifiedAt = report["verifiedAt"] as? TimeInterval else {
            print("{\"status\":\"not_verified\",\"message\":\"Open NextMeeting from its app bundle first.\"}")
            exit(1)
        }
        let fresh = Date().timeIntervalSince1970 - verifiedAt < 180
        report["isFresh"] = fresh
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let result = String(data: data, encoding: .utf8) { print(result) }
        exit(fresh && report["status"] as? String == "ready" ? 0 : 1)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var previewWindow: NSWindow?
    private var previewAnchor: NSButton?
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var store: CalendarStore!
    private let preferences = AppPreferences()
    private let navigation = PanelNavigation()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let isPreview = arguments.contains("--preview") || Bundle.main.object(forInfoDictionaryKey: "NextMeetingPreview") as? Bool == true
        let isInspection = arguments.contains("--inspect") || Bundle.main.object(forInfoDictionaryKey: "NextMeetingInspection") as? Bool == true
        let demo = arguments.contains("--demo") || isPreview
        let previewStateName = Bundle.main.object(forInfoDictionaryKey: "NextMeetingPreviewState") as? String
        let isPopoverPreview = isPreview && (arguments.contains("--preview-popover") || previewStateName == "popover")
        let previewState: CalendarPreviewState? = isPreview
            ? (arguments.contains("--preview-empty") || previewStateName == "empty" ? .empty
               : arguments.contains("--preview-denied") || previewStateName == "denied" ? .denied : nil)
            : nil
        store = CalendarStore(demo: demo, previewState: previewState)

        let root = MeetingPanel().environmentObject(store).environmentObject(preferences).environmentObject(navigation)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 340, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "NextMeeting")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        store.$meetings.combineLatest(store.$access, preferences.$showMeetingTitle)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &subscriptions)
        Publishers.CombineLatest4(store.$meetings, store.$access, navigation.$showingSettings, navigation.$selectedMeeting)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updatePanelSize() }
            .store(in: &subscriptions)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
        updateStatusItem()

        if isPreview || isInspection {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: isPopoverPreview ? 380 : 340,
                                                      height: isPopoverPreview ? 120 : 520),
                                  styleMask: isPopoverPreview ? [.titled, .closable] : [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = isPreview ? "NextMeeting Preview" : "NextMeeting"
            if isPopoverPreview {
                let label = NSTextField(labelWithString: "Sample meetings · Native popover")
                let button = NSButton(title: "Open sample popover", target: self, action: #selector(showPreviewPopover))
                button.bezelStyle = .rounded
                let stack = NSStackView(views: [label, button])
                stack.orientation = .vertical
                stack.alignment = .centerX
                stack.spacing = 14
                stack.translatesAutoresizingMaskIntoConstraints = false
                if let content = window.contentView {
                    content.addSubview(stack)
                    NSLayoutConstraint.activate([
                        stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                        stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
                    ])
                }
                previewAnchor = button
            } else {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.contentViewController = NSHostingController(rootView: root.padding(.top, 24).background(PreviewSurface()))
                window.setContentSize(NSSize(width: 340, height: 544))
            }
            window.center()
            if isPopoverPreview, let screen = window.screen {
                window.setFrameOrigin(NSPoint(x: window.frame.minX,
                                              y: screen.visibleFrame.maxY - window.frame.height - 60))
            }
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            previewWindow = window
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else if arguments.contains("--show") || store.access == .notDetermined {
            DispatchQueue.main.async { [weak self] in self?.showPopover() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let previewWindow {
            previewWindow.makeKeyAndOrderFront(nil)
        } else if !popover.isShown {
            showPopover()
        }
        return true
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open NextMeeting", action: #selector(openPanel), keyEquivalent: "")
            menu.addItem(withTitle: "Refresh Calendars", action: #selector(refreshCalendars), keyEquivalent: "r")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit NextMeeting", action: #selector(quit), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    @objc private func openPanel() { showPopover() }
    @objc private func refreshCalendars() { store.refresh() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func showPreviewPopover(_ sender: NSButton) {
        guard previewAnchor === sender else { return }
        navigation.reset()
        updatePanelSize()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        navigation.reset()
        store.refresh()
        preferences.updateLoginStatus()
        updatePanelSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func updatePanelSize() {
        guard let store else { return }
        let height = PanelLayout.height(meetingCount: store.meetings.count, access: store.access,
                                        showingSettings: navigation.showingSettings,
                                        showingDetails: navigation.selectedMeeting != nil)
        popover.contentSize = NSSize(width: 340, height: height)
        if previewAnchor == nil {
            previewWindow?.setContentSize(NSSize(width: 340, height: height + 24))
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button, let store else { return }
        let now = Date()
        if store.access != .granted {
            button.title = " NextMeeting"
            button.toolTip = "Connect your calendars to NextMeeting"
        } else if let meeting = MeetingLogic.nextMeeting(store.meetings, now: now) {
            let status = MeetingLogic.statusText(for: meeting, now: now)
            let title = meeting.title.count > 22 ? String(meeting.title.prefix(21)) + "…" : meeting.title
            button.title = preferences.showMeetingTitle ? " \(title) · \(status)" : " \(status)"
            button.toolTip = "\(meeting.title)\n\(meeting.startDate.formatted(date: .omitted, time: .shortened)) – \(meeting.endDate.formatted(date: .omitted, time: .shortened))"
        } else {
            button.title = " No meetings"
            button.toolTip = "No meetings in the next 24 hours"
        }
        if store.isDemo { button.title = " Preview ·" + button.title }
        button.setAccessibilityLabel("NextMeeting, \(button.title.trimmingCharacters(in: .whitespaces))")
    }
}
