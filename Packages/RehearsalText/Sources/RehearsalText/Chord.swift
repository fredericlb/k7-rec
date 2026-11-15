// Chord.swift: chord recognition and transposition, ported from packages/lyrics/src/chords.ts.
// A chord is a KNOWN vocabulary, not "any letters" (docs/text.md): "Bad" is a word, not a chord.

import Foundation

public struct Chord: Equatable, Sendable, CustomStringConvertible {
    public let root: String
    public let suffix: String
    public let bass: String?

    public var description: String { root + suffix + (bass.map { "/" + $0 } ?? "") }

    static let note = "[A-G](?:#|b|♯|♭)?"
    static let quality = "(?:maj|min|aug|dim|sus|add|m|M|Δ|°|ø|\\+|-)"
    static let ext = "(?:[0-9]|[#b][0-9]|\\([^)]*\\))"
    static let chordRe = Rx("^\(note)(?:\(quality)?\(ext)*)(?:/\(note))?\\z")
    static let noChord = Rx("^N\\.?C\\.?\\z", ignoreCase: true)
    static let flatMark = Rx("b|♭")

    /// True if `token` looks like a standalone chord symbol (`C#m7`, `G/B`, `N.C.`).
    public static func isChord(_ token: String) -> Bool {
        if token.isEmpty { return false }
        if noChord.test(token) { return true }
        return chordRe.test(token)
    }

    /// Root, suffix and slash bass of a chord symbol; nil for a non-chord and for `N.C.`.
    public init?(_ symbol: String) {
        guard Chord.isChord(symbol) else { return nil }
        let slash = symbol.firstIndex(of: "/")
        let head = slash.map { String(symbol[..<$0]) } ?? symbol
        guard let (root, rest) = Chord.splitRoot(head) else { return nil }
        self.root = root
        self.suffix = rest
        self.bass = slash.map { String(symbol[symbol.index(after: $0)...]) }
    }

    // A root letter with its optional accidental, and what follows it.
    static func splitRoot(_ s: String) -> (String, String)? {
        guard let first = s.first, "ABCDEFG".contains(first) else { return nil }
        var rootEnd = s.index(after: s.startIndex)
        if rootEnd < s.endIndex, "#b♯♭".contains(s[rootEnd]) { rootEnd = s.index(after: rootEnd) }
        return (String(s[..<rootEnd]), String(s[rootEnd...]))
    }

    static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flats = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    static let base: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]

    static func noteIndex(_ note: String) -> Int? {
        guard let letter = note.first, var idx = base[letter] else { return nil }
        let acc = note.dropFirst().first
        if acc == "#" || acc == "♯" { idx += 1 } else if acc == "b" || acc == "♭" { idx -= 1 }
        return ((idx % 12) + 12) % 12
    }

    static func transposeNote(_ note: String, _ semitones: Int, preferFlats: Bool) -> String {
        guard let idx = noteIndex(note) else { return note }
        let next = (((idx + semitones) % 12) + 12) % 12
        return (preferFlats ? flats : sharps)[next]
    }

    /// One chord moved: only the root and any slash bass move, and a non-chord does not.
    public static func transpose(_ chord: String, semitones: Int, preferFlats: Bool? = nil) -> String {
        if semitones == 0 || !isChord(chord) { return chord }
        let flat = preferFlats ?? flatMark.test(chord)
        guard let parts = Chord(chord) else { return chord }
        let newRoot = transposeNote(parts.root, semitones, preferFlats: flat) + parts.suffix
        guard let bass = parts.bass, !bass.isEmpty else { return newRoot }
        return newRoot + "/" + transposeNote(bass, semitones, preferFlats: flat)
    }
}

/// Every chord on a line moved, keeping the exact whitespace between tokens (docs/text.md).
public func transposeLine(_ line: String, semitones: Int) -> String {
    if semitones == 0 { return line }
    var out = ""
    var token = ""
    var inSpace = false
    func flush() {
        out += inSpace ? token : Chord.transpose(token, semitones: semitones)
        token = ""
    }
    for ch in line {
        if ch.isWhitespace != inSpace, !token.isEmpty { flush() }
        inSpace = ch.isWhitespace
        token.append(ch)
    }
    flush()
    return out
}
