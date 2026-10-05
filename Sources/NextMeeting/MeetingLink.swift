import Foundation

enum MeetingProvider: String, CaseIterable, Sendable {
    case zoom, teams, webex

    var nativeScheme: String {
        switch self {
        case .zoom: return "zoommtg"
        case .teams: return "msteams"
        case .webex: return "webex"
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .zoom: return ["us.zoom.xos"]
        case .teams: return ["com.microsoft.teams2", "com.microsoft.teams"]
        case .webex: return ["Cisco-Systems.Spark", "com.cisco.webexmeetingsapp", "com.webex.meetingmanager"]
        }
    }
}

struct NativeMeetingLink: Equatable, Sendable {
    let provider: MeetingProvider
    let url: URL
}

/// Conference links stay local. The browser always receives the original URL,
/// including any opaque password, registration token, context, or fragment.
enum MeetingLink {
    static func nativeLink(for url: URL) -> NativeMeetingLink? {
        guard MeetingLogic.isConferenceURL(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = url.host?.lowercased() else { return nil }

        if host == "teams.microsoft.com" || host == "teams.live.com" || host == "teams.cloud.microsoft" {
            // Microsoft's MSTEAMS handler replaces HTTPS; never prefix msteams:
            // to an HTTPS URL. Preserve the invitation's encoded payload.
            components.scheme = "msteams"
            return components.url.map { NativeMeetingLink(provider: .teams, url: $0) }
        }

        if host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "zoomgov.com" || host.hasSuffix(".zoomgov.com") {
            let path = components.path.split(separator: "/").map(String.init)
            let meetingID: String?
            if path.count == 2 && ["j", "w"].contains(path[0]) {
                meetingID = path[1]
            } else if path.count == 3 && path[0] == "wc" && path[1] == "join" {
                meetingID = path[2]
            } else {
                meetingID = nil
            }
            guard let meetingID, !meetingID.isEmpty,
                  meetingID.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            // The desktop contract uses confno, rather than the web /j path.
            // Keep the existing encoded query verbatim so +, %, duplicate keys,
            // and registration tokens cannot be changed by decoding/re-encoding.
            let existingQuery = components.percentEncodedQuery
            // Conflicting native control parameters cannot address this web link
            // faithfully. Leave resolution to the original invitation instead.
            let queryNames = components.queryItems?.map { $0.name.lowercased() } ?? []
            guard !queryNames.contains("confno"), !queryNames.contains("action"),
                  !queryNames.contains("zak") else { return nil }
            components.scheme = "zoommtg"
            components.path = "/join"
            components.percentEncodedQuery = "action=join&confno=" + meetingID
                + (existingQuery.map { "&" + $0 } ?? "")
            return components.url.map { NativeMeetingLink(provider: .zoom, url: $0) }
        }

        if host == "webex.com" || host.hasSuffix(".webex.com") {
            // Webex App's native handler wraps the complete HTTPS invitation.
            // MTID is opaque: converting it into a meeting number or SIP call
            // would discard information. Encode the whole nested URL once.
            let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            guard let invitation = url.absoluteString.addingPercentEncoding(withAllowedCharacters: unreserved),
                  let native = URL(string: "webex://meet?url=" + invitation) else { return nil }
            return NativeMeetingLink(provider: .webex, url: native)
        }

        return nil
    }
}

@MainActor
protocol MeetingLinkOpening {
    func applicationURL(for provider: MeetingProvider) -> URL?
    func openNative(_ url: URL, application: URL) async -> Bool
    func openBrowser(_ url: URL) async -> Bool
}

enum MeetingOpenResult: Equatable {
    case native(MeetingProvider), browser, failed
}

enum MeetingLinkRouter {
    @MainActor
    static func open(_ originalURL: URL, using opener: any MeetingLinkOpening) async -> MeetingOpenResult {
        guard MeetingLogic.isConferenceURL(originalURL) else { return .failed }
        if let native = MeetingLink.nativeLink(for: originalURL),
           let application = opener.applicationURL(for: native.provider),
           await opener.openNative(native.url, application: application) {
            return .native(native.provider)
        }
        return await opener.openBrowser(originalURL) ? .browser : .failed
    }
}
