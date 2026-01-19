import Foundation

enum MusicService: String, CaseIterable {
    case appleMusic
    case spotify

    var displayName: String {
        switch self {
        case .appleMusic:
            return "Apple Music"
        case .spotify:
            return "Spotify"
        }
    }
}
