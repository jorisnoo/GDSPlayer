import Foundation

enum MusicService: String, CaseIterable {
    case appleMusic
    case spotify
    case tidal

    var displayName: String {
        switch self {
        case .appleMusic:
            return "Apple Music"
        case .spotify:
            return "Spotify"
        case .tidal:
            return "Tidal"
        }
    }
}
