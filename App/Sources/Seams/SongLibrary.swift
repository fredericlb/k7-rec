// What the Songs screens need from the store; the real one wraps RehearsalStore.
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
}

protocol SongLibrary: AnyObject {
    var songs: [Song] { get }
    func importURLs(_ urls: [URL])
}

final class FakeSongLibrary: SongLibrary {
    private(set) var imported: [URL] = []
    let songs: [Song] = [
        Song(id: "1", title: "Blue Monday Jam", artist: "The Band", hasTab: true,
             chords: "Am       F\nG        C", lyrics: "{{00:04}} First line\n{{00:09}} Second line"),
        Song(id: "2", title: "Slow Waltz", artist: "Trio", hasSheets: true,
             chords: "D  A  Bm  G", lyrics: "Only words here"),
        Song(id: "3", title: "Untitled riff", artist: "", hasChords: false, hasLyrics: false),
    ]

    func importURLs(_ urls: [URL]) {
        imported += urls
        for url in urls { print("import:", url.path) }
    }
}
