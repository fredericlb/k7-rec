// The only file that touches the chords-db data (Resources/ChordsDB/guitar.json), as the web's chordDiagram.ts does.
// What a reader gets wrong: the lookup answers nil for what is not a chord; it never invents a fingering.
import Foundation
import RehearsalText

/// One guitar fingering; `frets` are relative to `baseFret` when that is above 1, -1 mutes a string.
struct ChordFingering: Equatable {
    var frets: [Int]
    var fingers: [Int]
    var baseFret: Int
    var barres: [Int]
    var capo: Bool
}

struct ChordDiagrams {
    private struct Entry: Decodable { var suffix: String; var positions: [Position] }
    private struct Position: Decodable { var frets: [Int]; var fingers: [Int]; var baseFret: Int; var barres: [Int]; var capo: Bool? }
    private struct Db: Decodable { var chords: [String: [Entry]] }

    private let db: [String: [Entry]]

    static let shared = ChordDiagrams(data: bundled)

    private static var bundled: Data {
        let url = Bundle(for: BundleToken.self).url(forResource: "guitar", withExtension: "json")
        return url.flatMap { try? Data(contentsOf: $0) } ?? Data()
    }
    private final class BundleToken {}

    init(data: Data) { db = (try? JSONDecoder().decode(Db.self, from: data))?.chords ?? [:] }

    // Root note to the database's key: sharps spelled out, enharmonics folded.
    private static let rootToDb = [
        "C": "C", "C#": "Csharp", "Db": "Csharp", "B#": "C", "D": "D", "D#": "Eb", "Eb": "Eb", "E": "E", "Fb": "E",
        "F": "F", "E#": "F", "F#": "Fsharp", "Gb": "Fsharp", "G": "G", "G#": "Ab", "Ab": "Ab", "A": "A", "A#": "Bb",
        "Bb": "Bb", "B": "B", "Cb": "B",
    ]

    private static let suffixAliases = [
        "": "major", "maj": "major", "M": "major", "m": "minor", "min": "minor", "-": "minor", "dim": "dim", "dim7": "dim7",
        "°": "dim", "°7": "dim7", "aug": "aug", "+": "aug", "sus": "sus4", "sus2": "sus2", "sus4": "sus4", "6": "6",
        "m6": "m6", "69": "69", "7": "7", "7sus4": "7sus4", "maj7": "maj7", "M7": "maj7", "m7": "m7", "m7b5": "m7b5",
        "ø": "m7b5", "9": "9", "maj9": "maj9", "m9": "m9", "add9": "add9", "madd9": "madd9", "11": "11", "m11": "m11",
        "13": "13", "m13": "m13", "maj13": "maj13", "7b5": "7b5", "7b9": "7b9", "7#9": "7#9", "mmaj7": "mmaj7",
    ]

    private static func norm(_ s: String) -> String { s.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b") }

    /// The first fingering for `symbol`: exact quality, then the slash form, then the bare triad; nil when unknown.
    func fingering(for symbol: String) -> ChordFingering? {
        guard let chord = Chord(symbol), let key = Self.rootToDb[Self.norm(chord.root)], let entries = db[key] else { return nil }
        let suffix = Self.norm(chord.suffix)
        let wanted = Self.suffixAliases[suffix] ?? suffix
        let minor = wanted.hasPrefix("m") && !wanted.hasPrefix("maj")
        func find(_ s: String) -> Entry? { entries.first { $0.suffix == s } }
        var match: Entry?
        if let bass = chord.bass { match = find((minor ? "m" : "") + "/" + Self.norm(bass)) }
        match = match ?? find(wanted) ?? find(minor ? "minor" : "major")
        return match?.positions.first.map {
            ChordFingering(frets: $0.frets, fingers: $0.fingers, baseFret: $0.baseFret, barres: $0.barres, capo: $0.capo ?? false)
        }
    }
}
