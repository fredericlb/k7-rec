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
    /// Whether the chords name any chord that has a diagram; read once when the song is built.
    var hasDiagrams = false
    var chords = ""
    var lyrics = ""
    var tab = ""
    var tags: [String] = []
    var sheets: [SongSheet] = []
    /// The song's folder under the songs folder, empty when no file names it.
    var folder = ""
    var added = Date()
    var audioURL: URL?
}

/// A file of the song's `sheets/` folder, in the sidecar's order and under its name.
struct SongSheet: Identifiable, Hashable {
    let id: String
    var name: String
    var url: URL
}

/// The three texts a song may carry, each one file of the song folder.
enum TextKind: String, CaseIterable, Identifiable {
    case lyrics, chords, tabs
    var id: String { rawValue }
    var title: String { self == .tabs ? "Tab" : rawValue.capitalized }
    var file: String { self == .lyrics ? "lyrics.txt" : self == .chords ? "chords.txt" : "tabs.txt" }
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
    /// Writes a text of the song's folder; an emptied text removes its file. Returns a message on failure.
    func saveText(_ kind: TextKind, _ text: String, for song: Song) async -> String?
    func addSheet(from url: URL, to song: Song) async -> String?
    func removeSheet(_ sheet: SongSheet, from song: Song) async -> String?
    func setTags(_ tags: [String], for song: Song) async -> String?
    /// Reads the store again, so `songs` holds what an import just filed.
    func refresh() async
}

extension SongLibrary {
    func refresh() async {}
}

@MainActor
final class FakeSongLibrary: SongLibrary {
    private(set) var imported: [URL] = []
    private(set) var songs: [Song] = [
        Song(id: "1", title: "Blue Monday Jam", artist: "The Band", hasTab: true, hasDiagrams: true,
             chords: "Am       F\nG        C", lyrics: "{{00:04}} First line\n{{00:09}} Second line"),
        Song(id: "2", title: "Slow Waltz", artist: "Trio", hasSheets: true, hasDiagrams: true,
             chords: "D  A  Bm  G", lyrics: "Only words here"),
        Song(id: "3", title: "Untitled riff", artist: "", hasChords: false, hasLyrics: false),
    ]

    func importURLs(_ urls: [URL]) async -> String? {
        imported += urls
        return nil
    }

    func wave(of song: Song) async -> Wave { .fake }

    func saveText(_ kind: TextKind, _ text: String, for song: Song) async -> String? {
        edit(song) { s in
            switch kind {
            case .lyrics: (s.lyrics, s.hasLyrics) = (text, !text.isEmpty)
            case .chords: (s.chords, s.hasChords) = (text, !text.isEmpty)
            case .tabs: (s.tab, s.hasTab) = (text, !text.isEmpty)
            }
        }
        return nil
    }

    func addSheet(from url: URL, to song: Song) async -> String? {
        edit(song) { $0.sheets.append(SongSheet(id: url.lastPathComponent, name: url.lastPathComponent, url: url)); $0.hasSheets = true }
        return nil
    }

    func removeSheet(_ sheet: SongSheet, from song: Song) async -> String? {
        edit(song) { $0.sheets.removeAll { $0.id == sheet.id }; $0.hasSheets = !$0.sheets.isEmpty }
        return nil
    }

    func setTags(_ tags: [String], for song: Song) async -> String? {
        edit(song) { $0.tags = tags }
        return nil
    }

    private func edit(_ song: Song, _ change: (inout Song) -> Void) {
        if let i = songs.firstIndex(where: { $0.id == song.id }) { change(&songs[i]) }
    }
}

extension Wave {
    static let fake = Wave(samples: (0..<150).map { 0.15 + 0.8 * abs(sin(Double($0) / 7)) }, duration: 30)
}
