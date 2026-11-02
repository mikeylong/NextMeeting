/// Sample and inspection windows must never register a menu bar item. macOS
/// remembers menu bar applications after they quit, including temporary builds.
enum AppLaunchMode {
    case menuBar
    case preview
    case inspection

    init(arguments: [String], info: [String: Any]) {
        if arguments.contains("--preview") || arguments.contains("--demo")
            || info["NextMeetingPreview"] as? Bool == true {
            self = .preview
        } else if arguments.contains("--inspect")
            || info["NextMeetingInspection"] as? Bool == true {
            self = .inspection
        } else {
            self = .menuBar
        }
    }

    var showsMenuBarItem: Bool { self == .menuBar }
}
