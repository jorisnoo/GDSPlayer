import Foundation

@MainActor
final class PreferencesManager {
    static let shared = PreferencesManager()

    private let musicServiceKey = "selectedMusicService"
    private let showVinylIconKey = "showVinylIcon"

    private init() {}

    var selectedMusicService: MusicService {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: musicServiceKey),
                  let service = MusicService(rawValue: rawValue) else {
                return .appleMusic
            }

            return service
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: musicServiceKey)
        }
    }

    var showVinylIcon: Bool {
        get {
            if UserDefaults.standard.object(forKey: showVinylIconKey) == nil {
                return true
            }

            return UserDefaults.standard.bool(forKey: showVinylIconKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showVinylIconKey)
        }
    }
}
