// ChordSheet.swift: classifies lyric text mixing "chords above lyrics" and inline `[C]` chords.
// Ported from packages/lyrics/src/chords.ts; lyrics stay plain strings, parsing is for display.

import Foundation

public struct Segment: Equatable, Sendable {
    public var chord: String?
    public var text: String
    public init(chord: String?, text: String) {
        self.chord = chord
        self.text = text
    }
}

public enum ParsedLine: Equatable, Sendable {
    case empty
    case section(label: String)
    case chords(text: String)
    case lyrics(segments: [Segment])
}

public enum ChordSheet {
    static let extraToken = Rx("^(?:\\||\\|\\||:\\||\\|:|x[0-9]+|[0-9]+x|N\\.?C\\.?|-|—)\\z", ignoreCase: true)
    static let tabLine = Rx("^[\\sA-Ga-g#b|:\\-–—0-9hpbrstx/\\\\~().^*=]+\\z")
    static let trailingMarks = Rx("[*~.!,']+\\z")
    static let bracketSection = Rx("^\\s*[\\[({]\\s*([^\\])}]+?)\\s*[\\])}]\\s*\\z")
    static let colonSection = Rx("^\\s*([A-Za-z][A-Za-z0-9_ '#/\\-]*?):\\s*\\z")
    static let inlineChord = Rx("[\\[(]([^\\])]+)[\\])]")
    static let forceMarker = Rx("\\s*%([ct])\\s*\\z")

    /// A line of tablature: a string's name or a bar, then fret numbers and techniques over dashes.
    public static func isTabLine(_ line: String) -> Bool {
        let t = line.jsTrimmed
        let dashes = t.reduce(0) { $1 == "-" ? $0 + 1 : $0 }
        return t.utf16Count >= 6 && t.contains("|") && dashes >= 3 && tabLine.test(t)
    }

    // A chord as a hand writes it on a sheet: `C**`, `G.`, the trailing marks being emphasis.
    static func chordish(_ token: String) -> Bool {
        Chord.isChord(trailingMarks.replacing(token, with: ""))
    }

    /// Looser than the renderer's test, for the sheets people type: `C**` is a chord line.
    public static func looseChordLine(_ line: String) -> Bool {
        var saw = false
        for tok in splitWhitespace(line) {
            if chordish(tok) { saw = true } else if !extraToken.test(tok) && tok != "/" { return false }
        }
        return saw
    }

    static func isChordLine(_ line: String) -> Bool {
        let tokens = splitWhitespace(line)
        if tokens.isEmpty || tokens[0].isEmpty { return false }
        var saw = false
        for tok in tokens {
            if Chord.isChord(tok) { saw = true } else if !extraToken.test(tok) { return false }
        }
        return saw
    }

    static func parseLyricLine(_ line: String) -> [Segment] {
        let ns = line as NSString
        var segments: [Segment] = []
        var last = 0
        var pending: String?
        for m in inlineChord.all(in: line) {
            guard let inner = m.group(1), Chord.isChord(inner) else { continue }
            let before = ns.substring(with: NSRange(location: last, length: m.start - last))
            if !(pending == nil && before.isEmpty) { segments.append(Segment(chord: pending, text: before)) }
            pending = inner
            last = m.end
        }
        let tail = ns.substring(from: last)
        if pending != nil || !tail.isEmpty { segments.append(Segment(chord: pending, text: tail)) }
        if segments.isEmpty { segments.append(Segment(chord: nil, text: line)) }
        return segments
    }

    /// Raw lyric text split into classified lines for rendering.
    public static func parse(_ text: String) -> [ParsedLine] {
        text.jsLines.map { raw in
            var line = LyricsTiming.strip(raw)
            var force: Character?
            if let marker = forceMarker.first(in: line) {
                force = marker.group(1) == "c" ? "c" : "t"
                line = (line as NSString).substring(to: marker.start)
            }
            if line.jsTrimmed.isEmpty { return .empty }
            if force != "c" {
                if let b = bracketSection.first(in: line), let label = b.group(1), !Chord.isChord(label) {
                    return .section(label: label)
                }
                if let c = colonSection.first(in: line), let label = c.group(1), !isChordLine(line) {
                    return .section(label: label)
                }
            }
            if force == "t" { return .lyrics(segments: parseLyricLine(line)) }
            if force == "c" || isChordLine(line) { return .chords(text: line) }
            return .lyrics(segments: parseLyricLine(line))
        }
    }

    /// Every distinct chord symbol used in the text, in first-seen order.
    public static func collectChords(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ c: String) { if seen.insert(c).inserted { out.append(c) } }
        for line in parse(text) {
            switch line {
            case .chords(let t): for tok in splitWhitespace(t) where Chord.isChord(tok) { add(tok) }
            case .lyrics(let segs): for seg in segs { if let c = seg.chord, !c.isEmpty { add(c) } }
            default: break
            }
        }
        return out
    }
}
