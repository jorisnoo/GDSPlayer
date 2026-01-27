import AppKit

enum MusicSearchService {
    @discardableResult
    static func openSearch(artist: String, track: String, service: MusicService) -> String? {
        let query = "\(artist) \(track)"

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let urlString: String
        switch service {
        case .appleMusic:
            urlString = "https://music.apple.com/search?term=\(encodedQuery)"
        case .spotify:
            urlString = "https://open.spotify.com/search/\(encodedQuery)"
        case .tidal:
            urlString = "https://tidal.com/search?q=\(encodedQuery)"
        }

        guard let url = URL(string: urlString) else {
            return nil
        }

        NSWorkspace.shared.open(url)

        return urlString
    }
}
