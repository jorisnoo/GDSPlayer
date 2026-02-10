import Foundation
import Aptabase

enum Analytics {
    private static var distribution: String {
        #if APP_STORE
        "app_store"
        #else
        "direct"
        #endif
    }

    private static let hasTrackedInstallKey = "AnalyticsHasTrackedInstall"

    private static var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: hasTrackedInstallKey)
    }

    static func initialize() {
        guard let appKey = Bundle.main.infoDictionary?["AptabaseAppKey"] as? String else {
            print("[Analytics] Missing AptabaseAppKey in Info.plist")
            return
        }

        Aptabase.shared.initialize(appKey: appKey)
    }

    static func appOpened() {
        if isFirstLaunch {
            track("installed")
            UserDefaults.standard.set(true, forKey: hasTrackedInstallKey)
        }

        track("app_opened")
    }

    static func appClosed() {
        track("app_closed")
    }

    static func playbackStarted() {
        track("playback_started")
    }

    static func playbackStopped() {
        track("playback_stopped")
    }

    static func heartbeat() {
        track("heartbeat")
    }

    static func outboundLinkClick(url: String) {
        track("outbound_link_click", props: ["url": url])
    }

    private static func track(_ event: String, props: [String: String] = [:]) {
        var allProps = props
        allProps["distribution"] = distribution

        Aptabase.shared.trackEvent(event, with: allProps)
        Aptabase.shared.flush()
    }
}
