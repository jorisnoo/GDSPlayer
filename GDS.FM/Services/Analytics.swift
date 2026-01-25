import AviaryInsights
import Foundation

enum Analytics {
    private static var isEnabled: Bool {
        #if DEBUG
        return false
        #else
        return Bundle.main.infoDictionary?["AnalyticsEnabled"] as? Bool ?? false
        #endif
    }

    private static var domain: String {
        Bundle.main.infoDictionary?["AnalyticsDomain"] as? String
            ?? Bundle.main.bundleIdentifier?.lowercased()
            ?? "unknown"
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static var serverURL: URL {
        let urlString = Bundle.main.infoDictionary?["AnalyticsServerURL"] as? String ?? "https://plausible.io/api"
        return URL(string: urlString)!
    }

    private static var distribution: String {
        #if APP_STORE
        "app_store"
        #else
        "direct"
        #endif
    }

    private static let plausible: Plausible? = {
        guard isEnabled else { return nil }
        return Plausible(defaultDomain: domain, serverURL: serverURL)
    }()

    static func track(_ name: String, path: String = "/", props: [String: String]? = nil) {
        guard let plausible else { return }
        var allProps = props ?? [:]
        allProps["distribution"] = distribution
        allProps["version"] = appVersion
        let event = Event(url: "app://\(domain)\(path)", name: name, props: allProps)
        plausible.postEvent(event)
    }

    static func appOpened() {
        track("App Open")
    }

    static func playbackStarted() {
        track("Playback Start")
    }

    static func playbackStopped() {
        track("Playback Stop")
    }

    static func outboundLinkClick(url: String) {
        track("Outbound Link: Click", props: ["url": url])
    }

    static func trackClick(artist: String, trackName: String, service: String) {
        track("Track Click", props: [
            "artist": artist,
            "track": trackName,
            "service": service
        ])
    }
}
