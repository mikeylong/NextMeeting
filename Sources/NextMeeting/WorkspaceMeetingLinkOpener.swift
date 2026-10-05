import AppKit

@MainActor
struct WorkspaceMeetingLinkOpener: MeetingLinkOpening {
    func applicationURL(for provider: MeetingProvider) -> URL? {
        // Bundle identifiers select the matching app even when a different app
        // has claimed the provider's URL scheme in Launch Services.
        for identifier in provider.bundleIdentifiers {
            if let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
               let bundle = Bundle(url: application), bundle.bundleIdentifier == identifier,
               let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
               types.contains(where: {
                   ($0["CFBundleURLSchemes"] as? [String])?.contains(where: {
                       $0.caseInsensitiveCompare(provider.nativeScheme) == .orderedSame
                   }) == true
               }) {
                return application
            }
        }
        return nil
    }

    func openNative(_ url: URL, application: URL) async -> Bool {
        await open(url, application: application)
    }

    func openBrowser(_ url: URL) async -> Bool {
        // Ask for the default HTTPS handler explicitly. Generic open(url) could
        // route the web invitation back into the meeting app that just failed.
        guard let probe = URL(string: "https://example.invalid"),
              let browser = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
        return await open(url, application: browser)
    }

    private func open(_ url: URL, application: URL) async -> Bool {
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
            return true
        } catch {
            // An NSError may contain the full invitation. Never log it.
            return false
        }
    }
}
