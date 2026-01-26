import Foundation

struct LiveInfo: Codable {
    let tracks: Tracks
    let shows: Shows
}

struct Tracks: Codable {
    let current: Track?
}

struct Track: Codable {
    let metadata: TrackMetadata?
}

struct TrackMetadata: Codable {
    let artistName: String?
    let trackTitle: String?
    let albumTitle: String?

    enum CodingKeys: String, CodingKey {
        case artistName = "artist_name"
        case trackTitle = "track_title"
        case albumTitle = "album_title"
    }
}

struct Shows: Codable {
    let current: Show?
}

struct Show: Codable {
    let name: String?
}
