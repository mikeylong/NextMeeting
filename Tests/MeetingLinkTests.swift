import Foundation

/// This fake never launches an app, a browser, or a real meeting.
@MainActor
private final class RecordingMeetingLinkOpener: MeetingLinkOpening {
    var installedApplications: [MeetingProvider: URL] = [:]
    var nativeSucceeds = true
    var browserSucceeds = true
    private(set) var requestedProviders: [MeetingProvider] = []
    private(set) var nativeRequests: [(url: URL, application: URL)] = []
    private(set) var browserRequests: [URL] = []

    func applicationURL(for provider: MeetingProvider) -> URL? {
        requestedProviders.append(provider)
        return installedApplications[provider]
    }

    func openNative(_ url: URL, application: URL) async -> Bool {
        nativeRequests.append((url, application))
        return nativeSucceeds
    }

    func openBrowser(_ url: URL) async -> Bool {
        browserRequests.append(url)
        return browserSucceeds
    }
}

@main
struct MeetingLinkTests {
    @MainActor
    static func main() async {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            assertions += 1
            guard condition() else { fatalError("Failed: \(description)") }
        }
        func url(_ value: String) -> URL { URL(string: value)! }
        let fixtureApplication = URL(fileURLWithPath: "/private/tmp/NextMeetingSyntheticApp.app")

        check(MeetingProvider.zoom.bundleIdentifiers == ["us.zoom.xos"], "Zoom uses its explicit application identifier")
        check(MeetingProvider.teams.bundleIdentifiers == ["com.microsoft.teams2", "com.microsoft.teams"], "current Teams is preferred before classic Teams")
        check(MeetingProvider.webex.bundleIdentifiers == ["Cisco-Systems.Spark", "com.cisco.webexmeetingsapp", "com.webex.meetingmanager"], "Webex application identifiers have a deterministic preference order")
        check(MeetingProvider.zoom.nativeScheme == "zoommtg" && MeetingProvider.teams.nativeScheme == "msteams" && MeetingProvider.webex.nativeScheme == "webex", "application selection requires the provider's matching registered native scheme")

        // Opaque query values deliberately exercise +, encoded +, %, duplicate
        // keys, encoded names, and a fragment. They contain no calendar data.
        let opaqueQuery = "pwd=synthetic+value%2B%252F&pwd=second%3Dvalue&%74oken=fixture%26only&context=%7B%22Tid%22%3A%22synthetic%22%7D"
        let opaqueFragment = "fixture%2Ffragment+value"
        for host in ["teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft"] {
            let source = "https://\(host)/l/meetup-join/19%3Ameeting_synthetic%40thread.v2/0?\(opaqueQuery)#\(opaqueFragment)"
            let native = MeetingLink.nativeLink(for: url(source))
            check(native?.provider == .teams, "supported Teams host selects Teams")
            check(native?.url.absoluteString == source.replacingOccurrences(of: "https://", with: "msteams://"), "Teams preserves all encoded invitation components")
        }
        let teamsMeet = url("https://teams.live.com/meet/00000000000?\(opaqueQuery)#\(opaqueFragment)")
        check(MeetingLink.nativeLink(for: teamsMeet)?.url.absoluteString == "msteams://teams.live.com/meet/00000000000?\(opaqueQuery)#\(opaqueFragment)", "Teams meet route preserves invitation parameters")

        for (host, path) in [("synthetic.zoom.us", "/j/00000000000"),
                             ("zoom.us", "/w/00000000000"), ("zoom.us", "/wc/join/00000000000"),
                             ("synthetic.zoomgov.com", "/j/00000000000")] {
            let native = MeetingLink.nativeLink(for: url("https://\(host)\(path)?\(opaqueQuery)#\(opaqueFragment)"))
            check(native?.provider == .zoom, "supported numeric Zoom invitation selects Zoom")
            check(native?.url.absoluteString == "zoommtg://\(host)/join?action=join&confno=00000000000&\(opaqueQuery)#\(opaqueFragment)", "Zoom preserves meeting ID and opaque encoded invitation parameters")
        }
        check(MeetingLink.nativeLink(for: url("https://zoom.us/j/00000000000"))?.url.absoluteString == "zoommtg://zoom.us/join?action=join&confno=00000000000", "Zoom invitation without query emits required join controls")

        let webexFixtures = [
            "https://synthetic.webex.com/meet/synthetic-room?\(opaqueQuery)#\(opaqueFragment)",
            "https://synthetic.webex.com/join/synthetic-room?\(opaqueQuery)#\(opaqueFragment)",
            "https://synthetic.webex.com/synthetic/j.php?MTID=mSyntheticFixture&\(opaqueQuery)#\(opaqueFragment)",
            "https://synthetic.webex.com/synthetic/g.php?MTID=mSyntheticFixture&\(opaqueQuery)#\(opaqueFragment)"
        ]
        for source in webexFixtures {
            let native = MeetingLink.nativeLink(for: url(source))
            let components = native.flatMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false) }
            check(native?.provider == .webex && native?.url.scheme == "webex" && native?.url.host == "meet", "supported Webex invitation selects its native meet route")
            check(components?.queryItems?.count == 1 && components?.queryItems?.first?.name == "url", "Webex passes one complete invitation parameter")
            check(components?.queryItems?.first?.value == source, "one Webex query decoding roundtrip preserves the entire original invitation")
            check(native?.url.fragment == nil && components?.queryItems?.contains(where: { $0.name == "pwd" || $0.name == "MTID" }) == false, "Webex keeps opaque password, meeting token, and fragment inside the nested invitation")
        }
        let webexEncoded = MeetingLink.nativeLink(for: url("https://synthetic.webex.com/meet/room~name?pwd=synthetic+value%2B%252F&pwd=second%3Dvalue#fixture%2Ffragment+value"))
        check(webexEncoded?.url.absoluteString == "webex://meet?url=https%3A%2F%2Fsynthetic.webex.com%2Fmeet%2Froom~name%3Fpwd%3Dsynthetic%2Bvalue%252B%25252F%26pwd%3Dsecond%253Dvalue%23fixture%252Ffragment%2Bvalue", "Webex encodes reserved characters once without decoding password values")

        let unsupportedZoom = [
            "https://zoom.us/my/synthetic-fixture?pwd=synthetic%2Bvalue",
            "https://zoom.us/j/00000000000/extra?pwd=synthetic",
            "https://zoom.us/j/00000000000?confno=11111111111&pwd=synthetic",
            "https://zoom.us/j/00000000000?%63onfno=11111111111&pwd=synthetic",
            "https://zoom.us/j/00000000000?AcTiOn=start&pwd=synthetic",
            "https://zoom.us/s/00000000000?\(opaqueQuery)#\(opaqueFragment)",
            "https://zoom.us/s/00000000000?zak=synthetic+host%2Btoken%252F&\(opaqueQuery)#\(opaqueFragment)",
            "https://zoom.us/j/00000000000?zak=synthetic+host%2Btoken%252F&\(opaqueQuery)#\(opaqueFragment)",
            "https://zoom.us/j/00000000000?%7Aak=synthetic+host%2Btoken%252F&\(opaqueQuery)#\(opaqueFragment)"
        ]
        for source in unsupportedZoom {
            let original = url(source)
            check(MeetingLink.nativeLink(for: original) == nil, "unsupported Zoom route or conflicting native controls are not rewritten")
            let opener = RecordingMeetingLinkOpener()
            opener.installedApplications[.zoom] = fixtureApplication
            let result = await MeetingLinkRouter.open(original, using: opener)
            check(result == .browser, "unsupported Zoom invitation uses browser")
            check(opener.requestedProviders.isEmpty && opener.nativeRequests.isEmpty, "unsupported Zoom invitation does not attempt an ambiguous native route")
            check(opener.browserRequests.map(\.absoluteString) == [source], "unsupported Zoom browser route preserves the complete original URL")
        }

        let nativeFixtures: [(MeetingProvider, URL)] = [
            (.zoom, url("https://synthetic.zoom.us/j/00000000000?\(opaqueQuery)#\(opaqueFragment)")),
            (.teams, teamsMeet)
        ] + webexFixtures.map { (.webex, url($0)) }
        for (provider, original) in nativeFixtures {
            let nativeSuccess = RecordingMeetingLinkOpener()
            nativeSuccess.installedApplications[provider] = fixtureApplication
            let successResult = await MeetingLinkRouter.open(original, using: nativeSuccess)
            check(successResult == .native(provider), "successful native open reports matching provider")
            check(nativeSuccess.requestedProviders == [provider], "router requests only the matching installed application")
            check(nativeSuccess.nativeRequests.count == 1 && nativeSuccess.nativeRequests.first?.application == fixtureApplication, "router uses the selected application exactly once")
            check(nativeSuccess.nativeRequests.first?.url == MeetingLink.nativeLink(for: original)?.url, "router opens the provider native URL")
            check(nativeSuccess.browserRequests.isEmpty, "successful native open never launches the browser")

            let unavailable = RecordingMeetingLinkOpener()
            let unavailableResult = await MeetingLinkRouter.open(original, using: unavailable)
            check(unavailableResult == .browser, "missing provider application falls back to browser")
            check(unavailable.requestedProviders == [provider] && unavailable.nativeRequests.isEmpty, "missing application does not issue a native open")
            check(unavailable.browserRequests.map(\.absoluteString) == [original.absoluteString], "missing application browser fallback preserves the original byte string")

            let nativeFailure = RecordingMeetingLinkOpener()
            nativeFailure.installedApplications[provider] = fixtureApplication
            nativeFailure.nativeSucceeds = false
            let failureResult = await MeetingLinkRouter.open(original, using: nativeFailure)
            check(failureResult == .browser, "failed native open falls back to browser")
            check(nativeFailure.nativeRequests.count == 1 && nativeFailure.browserRequests.map(\.absoluteString) == [original.absoluteString], "failed native open attempts one browser fallback with the complete original URL")

            let allFail = RecordingMeetingLinkOpener()
            allFail.installedApplications[provider] = fixtureApplication
            allFail.nativeSucceeds = false
            allFail.browserSucceeds = false
            let allFailResult = await MeetingLinkRouter.open(original, using: allFail)
            check(allFailResult == .failed, "failed browser fallback reports failure")
            check(allFail.nativeRequests.count == 1 && allFail.browserRequests.count == 1, "all failures do not cause retry loops")
        }

        let browserOnly = url("https://meet.google.com/abc-defg-hij?fixture=synthetic%2Bvalue#fixture")
        let browserOpener = RecordingMeetingLinkOpener()
        let browserResult = await MeetingLinkRouter.open(browserOnly, using: browserOpener)
        check(browserResult == .browser, "provider without a supported native route uses browser")
        check(browserOpener.requestedProviders.isEmpty && browserOpener.nativeRequests.isEmpty, "browser provider does not launch an unrelated application")
        check(browserOpener.browserRequests == [browserOnly], "browser provider preserves original invitation")

        let unsafeFixtures = [
            "http://zoom.us/j/00000000000", "https://zoom.us.evil.example/j/00000000000",
            "https://evilzoom.us/j/00000000000", "https://teams.microsoft.com.evil.example/meet/00000000000",
            "https://teams.live.com.evil.example/meet/00000000000", "https://webex.com.evil.example/meet/synthetic",
            "https://synthetic@zoom.us/j/00000000000", "https://zoom.us:8443/j/00000000000",
            "zoommtg://zoom.us/join?action=join&confno=00000000000", "file:///private/tmp/synthetic-meeting.html",
            "https://zoom.us/pricing", "https://teams.microsoft.com/"
        ]
        for source in unsafeFixtures {
            let original = url(source)
            check(MeetingLink.nativeLink(for: original) == nil, "unsafe or unrelated URL has no native route")
            let opener = RecordingMeetingLinkOpener()
            let result = await MeetingLinkRouter.open(original, using: opener)
            check(result == .failed, "unsafe or unrelated URL is rejected")
            check(opener.requestedProviders.isEmpty && opener.nativeRequests.isEmpty && opener.browserRequests.isEmpty, "rejected URL never opens an application or browser")
        }
        print("Meeting link routing: \(assertions) checks passed.")
    }
}
