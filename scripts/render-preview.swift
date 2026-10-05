import AppKit
import SwiftUI

/// Render only sample data. This does not capture the screen or read calendars.
@main
struct RenderPreview {
    @MainActor
    static func main() throws {
        let destination = CommandLine.arguments.dropFirst().first ?? "Design/NextMeeting-preview.png"
        let light = CommandLine.arguments.contains("--light")
        NSApplication.shared.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        let store = CalendarStore(demo: true)
        let navigation = PanelNavigation()
        if CommandLine.arguments.contains("--details") { navigation.selectedMeeting = store.meetings.first }
        let view = MeetingPanel()
            .environmentObject(store)
            .environmentObject(AppPreferences())
            .environmentObject(navigation)
            .environment(\.colorScheme, light ? .light : .dark)
            .background(PreviewSurface())
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.12), lineWidth: 0.75))
            .padding(16)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 372, height: 552),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 372, height: 552)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "NextMeetingPreview", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not render sample schedule"])
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "NextMeetingPreview", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode sample schedule"])
        }
        try png.write(to: URL(fileURLWithPath: destination))
        store.stopObserving()
        print("Rendered \(destination)")
    }
}
