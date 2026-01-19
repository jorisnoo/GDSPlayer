import AppKit

enum MusicSearchService {
    static func openSearch(artist: String, track: String, service: MusicService) {
        let query = "\(artist) \(track)"

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        let urlString: String
        switch service {
        case .appleMusic:
            urlString = "https://music.apple.com/search?term=\(encodedQuery)"
        case .spotify:
            urlString = "https://open.spotify.com/search/\(encodedQuery)"
        }

        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
