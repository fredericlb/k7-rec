// What the Songs screens need from the store; the real one is Live/StoreSongLibrary.
import Foundation

struct Song: Identifiable, Hashable {
    let id: String
    var title: String
    var artist: String
    var hasChords = true
    var hasLyrics = true
    var hasTab = false
    var hasSheets = false
    var chords = ""
    var lyrics = ""
    var added = Date()
    var audioURL: URL?
}

/// A waveform: levelled RMS samples in 0...1 and the seconds they cover.
struct Wave: Hashable {
    var samples: [Double]
    var duration: TimeInterval
}

@MainActor
protocol SongLibrary: AnyObject {
    var songs: [Song] { get }
    /// Imports folders and audio files; returns a message when something failed.
    func importURLs(_ urls: [URL]) async -> String?
    func wave(of song: Song) async -> Wave
}

@MainActor
final class FakeSongLibrary: SongLibrary {
    private(set) var imported: [URL] = []
    let songs: [Song] = [
        Song(id: "1", title: "Blue Monday Jam", artist: "The Band", hasTab: true,
             chords: "Am       F\nG        C", lyrics: "{{00:04}} First line\n{{00:09}} Second line"),
        Song(id: "2", title: "Slow Waltz", artist: "Trio", hasSheets: true,
             chords: "D  A  Bm  G", lyrics: "Only words here"),
        Song(id: "3", title: "Untitled riff", artist: "", hasChords: false, hasLyrics: false),
    ]

    func importURLs(_ urls: [URL]) async -> String? {
        imported += urls
        return nil
    }

    func wave(of song: Song) async -> Wave { .fake }
}

extension Wave {
    static let fake = Wave(samples: (0..<150).map { 0.15 + 0.8 * abs(sin(Double($0) / 7)) }, duration: 30)
}
