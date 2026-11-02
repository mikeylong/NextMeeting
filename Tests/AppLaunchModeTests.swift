@main
enum AppLaunchModeTests {
    static func main() {
        let normal = AppLaunchMode(arguments: ["NextMeeting"], info: [:])
        precondition(normal == .menuBar && normal.showsMenuBarItem)
        precondition(AppLaunchMode(arguments: ["NextMeeting", "--show"], info: [:]).showsMenuBarItem)

        for flag in ["--preview", "--demo", "--inspect"] {
            let mode = AppLaunchMode(arguments: ["NextMeeting", flag], info: [:])
            precondition(!mode.showsMenuBarItem, "\(flag) must not register a menu bar item")
            precondition(mode == (flag == "--inspect" ? .inspection : .preview))
        }
        for state in ["agenda", "empty", "denied", "light", "popover"] {
            let mode = AppLaunchMode(arguments: ["NextMeeting"], info: [
                "NextMeetingPreview": true, "NextMeetingPreviewState": state
            ])
            precondition(mode == .preview && !mode.showsMenuBarItem,
                         "A preview bundle launched by Finder must stay out of the menu bar")
        }
        let inspection = AppLaunchMode(arguments: ["NextMeeting"], info: ["NextMeetingInspection": true])
        precondition(inspection == .inspection && !inspection.showsMenuBarItem)
        let disabled = AppLaunchMode(arguments: ["NextMeeting"], info: [
            "NextMeetingPreview": false, "NextMeetingInspection": false
        ])
        precondition(disabled.showsMenuBarItem)
        let sampleInspection = AppLaunchMode(arguments: ["NextMeeting", "--demo", "--inspect"], info: [:])
        precondition(sampleInspection == .preview, "Sample data takes priority over real calendar inspection")
        print("App launch mode checks passed: only normal launches create a menu bar item.")
    }
}
