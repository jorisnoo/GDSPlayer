import Foundation

enum Analytics {
    private static var isEnabled: Bool {
        Bundle.main.infoDictionary?["AnalyticsEnabled"] as? Bool ?? false
    }

    private static var apiURL: URL? {
        guard let urlString = Bundle.main.infoDictionary?["AnalyticsAPIURL"] as? String else {
            return nil
        }
        return URL(string: urlString)?.appending(path: "api/events")
    }

    private static var apiToken: String? {
        Bundle.main.infoDictionary?["AnalyticsAPIToken"] as? String
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static var distribution: String {
        #if APP_STORE
        "app_store"
        #else
        "direct"
        #endif
    }

    private static let userUUIDKey = "AnalyticsUserUUID"
    private static let hasTrackedInstallKey = "AnalyticsHasTrackedInstall"

    private static var userUUID: String {
        if let existingUUID = UserDefaults.standard.string(forKey: userUUIDKey) {
            return existingUUID
        }
        let newUUID = UUID().uuidString
        UserDefaults.standard.set(newUUID, forKey: userUUIDKey)
        return newUUID
    }

    private static var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: hasTrackedInstallKey)
    }

    static func appOpened() {
        guard isEnabled else {
            print("[Analytics] Skipped (disabled): app_opened")
            return
        }

        if isFirstLaunch {
            track("installed")
            UserDefaults.standard.set(true, forKey: hasTrackedInstallKey)
        }

        track("app_opened")
    }

    static func track(_ eventType: String, url: String? = nil, props: [String: String]? = nil) {
        guard isEnabled else {
            print("[Analytics] Skipped (disabled): \(eventType)")
            return
        }

        var allProps = props ?? [:]
        allProps["distribution"] = distribution
        if let url {
            allProps["url"] = url
        }

        print("[Analytics] Sending: \(eventType) with props: \(allProps)")

        Task {
            await sendEvent(eventType: eventType, props: allProps)
        }
    }

    static func outboundLinkClick(url: String) {
        track("outbound_link_click", url: url)
    }

    private static func sendEvent(eventType: String, props: [String: String]) async {
        guard let apiURL, let apiToken else {
            print("[Analytics] Failed: Missing API URL or token")
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "user_uuid": userUUID,
            "event_type": eventType,
            "version": appVersion,
            "props": props
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    print("[Analytics] Success: \(eventType)")
                } else {
                    let body = String(data: data, encoding: .utf8) ?? "no body"
                    print("[Analytics] Failed: HTTP \(httpResponse.statusCode) - \(body)")
                }
            }
        } catch {
            print("[Analytics] Failed: \(error)")
        }
    }
}
