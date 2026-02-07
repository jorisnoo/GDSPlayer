import Foundation

#if !APP_STORE
import AppUpdater
#endif

@MainActor
final class PreferencesManager {
    static let shared = PreferencesManager()

    private let musicServiceKey = "selectedMusicService"
    private let showVinylIconKey = "showVinylIcon"
    private let clickToPlayKey = "clickToPlay"
    private let deferredUpdateKey = "deferredUpdate"

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

    var clickToPlay: Bool {
        get {
            if UserDefaults.standard.object(forKey: clickToPlayKey) == nil {
                return true
            }

            return UserDefaults.standard.bool(forKey: clickToPlayKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: clickToPlayKey)
        }
    }

    #if !APP_STORE
    var deferredUpdate: DeferredUpdate? {
        get {
            guard let data = UserDefaults.standard.data(forKey: deferredUpdateKey),
                  let update = try? JSONDecoder().decode(DeferredUpdate.self, from: data) else {
                return nil
            }
            return update
        }
        set {
            if let update = newValue,
               let data = try? JSONEncoder().encode(update) {
                UserDefaults.standard.set(data, forKey: deferredUpdateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: deferredUpdateKey)
            }
        }
    }
    #endif
}
