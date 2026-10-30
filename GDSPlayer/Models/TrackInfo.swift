import Foundation

struct LiveInfo: Codable {
    let tracks: Tracks
    let shows: Shows
}

struct Tracks: Codable {
    let current: Track?
}

struct Track: Codable {
    let type: String?
    let metadata: TrackMetadata?

    /// Library tracks carry structured metadata; webstream relays only expose
    /// an "Artist - Title" string in `live_metadata`.
    var artistAndTitle: (artist: String?, title: String?) {
        guard type == "webstream" else {
            return (metadata?.artistName, metadata?.trackTitle)
        }

        guard let track = metadata?.liveMetadata?.artistAndTitle else { return (nil, nil) }
        return (track.artist, track.title)
    }
}

extension String {
    /// Splits an "Artist - Title" string; both parts must be present.
    var artistAndTitle: (artist: String, title: String)? {
        guard let separator = range(of: " - ") else { return nil }

        let artist = self[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
        let title = self[separator.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !artist.isEmpty, !title.isEmpty else { return nil }
        return (artist, title)
    }

    /// The stream's ICY title prefixes webstream relays with their source and an
    /// empty field: "Helvetica -  - Artist - Title".
    var streamTitleArtistAndTitle: (artist: String, title: String)? {
        let track = range(of: " -  - ").map { String(self[$0.upperBound...]) } ?? self
        return track.artistAndTitle
    }
}

struct TrackMetadata: Codable {
    let artistName: String?
    let trackTitle: String?
    let albumTitle: String?
    let liveMetadata: String?

    enum CodingKeys: String, CodingKey {
        case artistName = "artist_name"
        case trackTitle = "track_title"
        case albumTitle = "album_title"
        case liveMetadata = "live_metadata"
    }
}

struct Shows: Codable {
    let current: Show?
}

struct Show: Codable {
    let name: String?
}
