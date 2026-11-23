// PianoChord.swift: a chord symbol as keys to press, in root position with the right hand's usual fingering;
// a slash chord's bass is the left hand's, an octave below. An unknown quality falls back to its triad.
import Foundation

/// The keys of one chord, counted in semitones from a C; a view draws only the stretch they need.
public struct PianoVoicing: Equatable, Sendable {
    /// The right hand's keys, low to high.
    public let keys: [Int]
    /// The right hand's fingers for `keys`: 1 is the thumb.
    public let fingers: [Int]
    /// The left hand's key, for a slash chord.
    public let bass: Int?
}

public enum PianoChord {
    // Semitones above the root; the longest chords drop a tone so the hand holds five keys at most.
    static let intervals: [String: [Int]] = [
        "": [0, 4, 7], "m": [0, 3, 7], "dim": [0, 3, 6], "dim7": [0, 3, 6, 9], "aug": [0, 4, 8],
        "sus2": [0, 2, 7], "sus4": [0, 5, 7], "5": [0, 7], "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9], "69": [0, 4, 7, 9, 14],
        "7": [0, 4, 7, 10], "7sus4": [0, 5, 7, 10], "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "m7b5": [0, 3, 6, 10],
        "mmaj7": [0, 3, 7, 11], "7b5": [0, 4, 6, 10], "7#5": [0, 4, 8, 10], "7b9": [0, 4, 7, 10, 13], "7#9": [0, 4, 7, 10, 15],
        "9": [0, 4, 7, 10, 14], "maj9": [0, 4, 7, 11, 14], "m9": [0, 3, 7, 10, 14], "add9": [0, 4, 7, 14], "madd9": [0, 3, 7, 14],
        "11": [0, 7, 10, 14, 17], "m11": [0, 3, 10, 14, 17], "13": [0, 4, 10, 14, 21], "m13": [0, 3, 10, 14, 21],
        "maj13": [0, 4, 11, 14, 21],
    ]

    static let aliases: [String: String] = [
        "maj": "", "M": "", "min": "m", "-": "m", "°": "dim", "°7": "dim7", "+": "aug", "sus": "sus4", "2": "sus2",
        "M7": "maj7", "Δ": "maj7", "Δ7": "maj7", "ø": "m7b5", "ø7": "m7b5", "min7": "m7", "-7": "m7", "aug7": "7#5",
        "+7": "7#5", "m(maj7)": "mmaj7", "mM7": "mmaj7", "add2": "add9", "7(b9)": "7b9", "7(#9)": "7#9",
    ]

    /// The right hand's fingers for so many keys.
    static func fingers(_ n: Int) -> [Int] {
        switch n {
        case 1: [1]
        case 2: [1, 5]
        case 3: [1, 3, 5]
        case 4: [1, 2, 3, 5]
        default: Array(1...min(n, 5))
        }
    }

    /// The keys of `symbol`, nil for what is not a chord.
    public static func voicing(_ symbol: String) -> PianoVoicing? {
        guard let chord = Chord(symbol), let root = Chord.noteIndex(chord.root) else { return nil }
        let suffix = chord.suffix.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        let wanted = aliases[suffix] ?? suffix
        let minor = wanted.hasPrefix("m") && !wanted.hasPrefix("maj")
        let steps = intervals[wanted] ?? intervals[minor ? "m" : ""]!
        let bass = chord.bass.flatMap(Chord.noteIndex)
        // With a bass, the right hand moves up an octave so the left has the lowest one to itself.
        let start = root + (bass == nil ? 0 : 12)
        let keys = steps.map { start + $0 }
        return PianoVoicing(keys: keys, fingers: fingers(keys.count), bass: bass)
    }
}
