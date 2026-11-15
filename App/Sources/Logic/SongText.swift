// The song screen's pure text logic: transposed lines, the line being sung, tab grids, LRC and re-timing.
// What a reader gets wrong: a timecode stays in the file; display lines are stripped, indexes are the file's.
import Foundation
import RehearsalText

enum SongText {
    /// A parsed line moved by `semitones`; section labels and plain words stay.
    static func transposed(_ line: ParsedLine, by semitones: Int) -> ParsedLine {
        guard semitones != 0 else { return line }
        switch line {
        case .chords(let text): return .chords(text: transposeLine(text, semitones: semitones))
        case .lyrics(let segments):
            return .lyrics(segments: segments.map { Segment(chord: $0.chord.map { Chord.transpose($0, semitones: semitones) }, text: $0.text) })
        default: return line
        }
    }

    /// The text's lines as shown: one per file line, timecodes taken off.
    static func displayLines(_ text: String, semitones: Int) -> [ParsedLine] {
        ChordSheet.parse(text).map { transposed($0, by: semitones) }
    }

    /// The line sung at `seconds` (the file's line index), nil before the first timed line.
    static func activeLine(_ text: String, at seconds: Double) -> Int? {
        LyricsTiming.lineAt(LyricsTiming.byLine(text), seconds: seconds)
    }

    /// Where a tap on a timed line seeks: `lead` seconds early, never before the start.
    static func seekTime(line: Int, in text: String, lead: Double) -> Double? {
        LyricsTiming.byLine(text).first { $0.line == line }.map { max(0, $0.t - lead) }
    }

    /// Every chord the song uses, moved, each once: the chords text first, then the lyrics' inline ones.
    static func diagramChords(chords: String, lyrics: String, semitones: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for symbol in ChordSheet.collectChords(chords) + ChordSheet.collectChords(lyrics) {
            let moved = Chord.transpose(symbol, semitones: semitones)
            if Chord(moved) != nil, seen.insert(moved).inserted { out.append(moved) }
        }
        return out
    }

    /// One monospaced row per string of a tab system, every string on the same column grid.
    static func gridRows(_ system: TabSystem) -> [String] {
        let width = system.strings.map { $0.label.count }.max() ?? 0
        return system.strings.map { string in
            var cells = [Character](repeating: "-", count: max(system.cols, 0))
            for bar in system.bars where bar < cells.count { cells[bar] = "|" }
            for event in string.events {
                for (offset, ch) in event.text.enumerated() where event.col + offset < cells.count { cells[event.col + offset] = ch }
            }
            return string.label.padding(toLength: width, withPad: " ", startingAt: 0) + String(cells)
        }
    }

    /// Lyrics timed from an LRC file's text, or the reason it could not be.
    static func timedLyrics(_ lyrics: String, lrc: String) -> Result<(text: String, placed: Int, total: Int), TextEditError> {
        switch LRC.merge(lyrics: lyrics, lrc: lrc) {
        case .ok(let text, let placed, let total): .success((text, placed, total))
        case .empty: .failure(.noTimedLines)
        }
    }

    /// The chords re-timed after a lyrics edit; nil when they carry no timecodes of their own to keep.
    static func retimedChords(chords: String, lyrics: String) -> String? {
        guard LyricsTiming.hasTimecodes(chords), LyricsTiming.hasTimecodes(lyrics) else { return nil }
        if case .ok(let text, _, _) = LRC.mergeTimedSheet(target: chords, timedSheet: lyrics) { return text }
        return nil
    }
}

enum TextEditError: Error, Equatable {
    case noTimedLines
    var message: String { "That file has no timed lines." }
}
