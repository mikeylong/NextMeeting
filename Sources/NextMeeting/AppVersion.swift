import Foundation

enum AppVersion {
    static var menuTitle: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else { return "Version unavailable" }
        return "Version \(version)"
    }
}
