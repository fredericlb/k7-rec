// What the stems sheet needs: the stems a song has, making them, dropping them; the real one is Live/LiveStemMaker.
import Foundation
import RehearsalStems

@MainActor
protocol StemMaking: AnyObject {
    /// Whether a separation model is installed, so the sheet can say what is missing before it offers the work.
    var hasModel: Bool { get }
    func existing(for song: Song) -> [Stem: URL]?
    /// Separates the song's audio; returns a message on failure, nil on success and on a cancel.
    func separate(_ song: Song, progress: @escaping @Sendable (Double) -> Void) async -> String?
    func remove(for song: Song)
    /// The song without its voice, when it was made; it goes with the stems.
    func instrumentalURL(for song: Song) -> URL?
    /// Mixes the instrumental from the stems; returns a message on failure.
    func makeInstrumental(for song: Song) async -> String?
}

@MainActor
final class FakeStemMaker: StemMaking {
    var hasModel = true
    var made: Set<String> = []
    var failure: String?

    func existing(for song: Song) -> [Stem: URL]? {
        made.contains(song.id) ? Dictionary(uniqueKeysWithValues: Stem.allCases.map { ($0, URL(fileURLWithPath: "/dev/null")) }) : nil
    }

    func separate(_ song: Song, progress: @escaping @Sendable (Double) -> Void) async -> String? {
        progress(1)
        if failure == nil { made.insert(song.id) }
        return failure
    }

    func remove(for song: Song) { made.remove(song.id); instrumental.remove(song.id) }

    var instrumental: Set<String> = []
    func instrumentalURL(for song: Song) -> URL? { instrumental.contains(song.id) ? URL(fileURLWithPath: "/dev/null") : nil }
    func makeInstrumental(for song: Song) async -> String? {
        guard made.contains(song.id) else { return "No stems." }
        instrumental.insert(song.id)
        return nil
    }
}
