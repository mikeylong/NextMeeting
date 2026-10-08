import Foundation

enum AppVersion {
    static var menuTitle: String {
        menuTitle(for: .main)
    }

    static func menuTitle(for bundle: Bundle) -> String {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else { return "Version unavailable" }
        if let identifier = bundle.object(forInfoDictionaryKey: "NextMeetingBuildIdentifier") as? String,
           !identifier.isEmpty {
            return "Version \(version) (local \(identifier))"
        }
        return "Version \(version)"
    }
}
