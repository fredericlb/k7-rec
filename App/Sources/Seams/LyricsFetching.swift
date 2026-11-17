// What the song screens need to find a song's lyrics online; the real one is Live/LRCLibClient.
import Foundation

struct FoundLyrics: Equatable, Sendable {
    /// The words alone, one line per row.
    var plain: String
    /// The same lines with LRC timecodes, nil when the service only has the words.
    var synced: String?
}

protocol LyricsFetching: Sendable {
    /// The lyrics of a song, nil when the service has none; a thrown error is a network failure.
    func find(title: String, artist: String, audio: URL?) async throws -> FoundLyrics?
}

struct FakeLyricsFetcher: LyricsFetching {
    var result: FoundLyrics?
    var fails = false

    func find(title: String, artist: String, audio: URL?) async throws -> FoundLyrics? {
        if fails { throw URLError(.notConnectedToInternet) }
        return result
    }
}
