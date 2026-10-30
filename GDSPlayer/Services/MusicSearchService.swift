import AppKit

enum MusicSearchService {
    // Characters such as & and + would otherwise split or alter the query value.
    private static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#/"))

    @discardableResult
    static func openSearch(artist: String, track: String, service: MusicService) async -> String? {
        let query = "\(artist) \(track)".trimmingCharacters(in: .whitespaces)

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) else {
            return nil
        }

        let urlString: String
        switch service {
        case .appleMusic:
            // The Music app ignores search links, so open the best matching song when there is one.
            urlString = await appleMusicSongURL(encodedQuery: encodedQuery)
                ?? "https://music.apple.com/search?term=\(encodedQuery)"
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

    private static func appleMusicSongURL(encodedQuery: String) async -> String? {
        var urlString = "https://itunes.apple.com/search?term=\(encodedQuery)&media=music&entity=song&limit=1"
        if let region = Locale.current.region?.identifier {
            urlString += "&country=\(region)"
        }

        guard let url = URL(string: urlString) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(ITunesSearchResponse.self, from: data).results.first?.trackViewUrl
        } catch {
            print("Failed to look up Apple Music track: \(error)")
            return nil
        }
    }
}

private struct ITunesSearchResponse: Decodable {
    let results: [Song]

    struct Song: Decodable {
        let trackViewUrl: String
    }
}
