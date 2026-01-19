import Foundation

@MainActor
final class PreferencesManager {
    static let shared = PreferencesManager()

    private let musicServiceKey = "selectedMusicService"

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
}
