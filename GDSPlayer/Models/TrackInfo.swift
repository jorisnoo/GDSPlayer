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

        guard let liveMetadata = metadata?.liveMetadata,
              let separator = liveMetadata.range(of: " - ")
        else { return (nil, nil) }

        let artist = liveMetadata[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
        let title = liveMetadata[separator.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !artist.isEmpty, !title.isEmpty else { return (nil, nil) }
        return (artist, title)
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
