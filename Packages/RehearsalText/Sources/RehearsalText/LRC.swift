// LRC.swift: LRC lyrics as timed lines, merged onto a song's own sheet as `{{MM:SS.cc}}` codes.
// What reads wrong: an LRC's `[01:23.45]` would look like a chord or a section, hence `{{...}}`.

import Foundation

public struct LrcLine: Equatable, Sendable {
    public var t: Double
    public var text: String
    public init(t: Double, text: String) {
        self.t = t
        self.text = text
    }
}

public struct SungLine: Equatable, Sendable {
    public var line: Int
    public var text: String
}

public enum LrcTimecoding: Equatable, Sendable {
    /// The sheet with codes at the start of each placed line; `placed` fetched lines of `total` found one.
    case ok(lyrics: String, placed: Int, total: Int)
    case empty
}

public enum LRC {
    /// A sheet line at least this close to a fetched line is where its timecode goes.
    public static let timecodeThreshold = 0.5

    static let leadingStamp = Rx("^\\s*\\[([0-9]{1,3}):([0-9]{1,2}(?:[.:][0-9]{1,3})?)\\]")
    static let wordStamp = Rx("<[0-9]{1,3}:[0-9]{1,2}(?:[.:][0-9]{1,3})?>")
    static let offsetTag = Rx("^\\s*\\[offset:\\s*([+-]?[0-9]+)\\s*\\]", ignoreCase: true, multiline: true)
    static let marks = Rx("\\p{M}")
    static let notWord = Rx("[^\\p{L}\\p{N}\\s]")

    /// The timed lines of an LRC file in time order; a line with several stamps is sung several times.
    public static func parse(_ source: String) -> [LrcLine] {
        let offset = Double(offsetTag.first(in: source)?.group(1) ?? "0").map { $0 / 1000 } ?? 0
        var out: [LrcLine] = []
        for raw in source.jsLines {
            var stamps: [Double] = []
            var rest = raw
            while let m = leadingStamp.first(in: rest) {
                let min = Double(m.group(1) ?? "") ?? 0
                let sec = Double((m.group(2) ?? "").replacingOccurrences(of: ":", with: ".")) ?? 0
                stamps.append(min * 60 + sec)
                rest = (rest as NSString).substring(from: m.end)
            }
            let text = wordStamp.replacing(rest, with: "").jsTrimmed
            if stamps.isEmpty || text.isEmpty { continue }
            for s in stamps { out.append(LrcLine(t: max(0, s - offset), text: text)) }
        }
        // A stable sort, as JS's is: equal times keep file order.
        return out.enumerated().sorted { ($0.element.t, $0.offset) < ($1.element.t, $1.offset) }.map(\.element)
    }

    /// A line as the matcher compares it: no accents, no case, no punctuation, single spaces.
    public static func normalizeLine(_ line: String) -> String {
        let bare = marks.replacing(line.decomposedStringWithCanonicalMapping, with: "").lowercased()
        let spaced = notWord.replacing(bare, with: " ")
        return Rx.whitespaceRun.replacing(spaced, with: " ").jsTrimmed
    }

    /// The sung lines of a chord sheet by line index: chords, tablature, sections and blanks left out.
    public static func lyricLines(_ lyrics: String) -> [SungLine] {
        let raw = lyrics.jsLines
        var out: [SungLine] = []
        for (line, parsed) in ChordSheet.parse(lyrics).enumerated() {
            guard case .lyrics(let segments) = parsed else { continue }
            let bare = LyricsTiming.strip(line < raw.count ? raw[line] : "")
            if ChordSheet.isTabLine(bare) || ChordSheet.looseChordLine(bare) { continue }
            let text = normalizeLine(segments.map(\.text).joined())
            if !text.isEmpty { out.append(SungLine(line: line, text: text)) }
        }
        return out
    }

    /// Writes an LRC's times into a sheet, touching nothing else; codes already there are replaced.
    public static func merge(lyrics: String, lrc source: String) -> LrcTimecoding {
        timeLines(lyrics, parse(source))
    }

    /// The same timing from a TIMED SHEET: its timed sung lines are the lines to place on `target`.
    public static func mergeTimedSheet(target: String, timedSheet: String) -> LrcTimecoding {
        let raw = timedSheet.jsLines
        var lines: [LrcLine] = []
        for l in lyricLines(timedSheet) {
            if let t = LyricsTiming.timecode(of: l.line < raw.count ? raw[l.line] : "") {
                lines.append(LrcLine(t: t, text: l.text))
            }
        }
        return timeLines(target, lines)
    }

    // The one matcher both timings share: timed lines placed on a sheet's sung lines, in order.
    static func timeLines(_ lyrics: String, _ timed: [LrcLine]) -> LrcTimecoding {
        let lrc = timed.filter { !normalizeLine($0.text).isEmpty }
        if lrc.isEmpty { return .empty }
        if lyrics.jsTrimmed.isEmpty {
            let text = lrc.map { "\(LyricsTiming.format($0.t)) \($0.text)" }.joined(separator: "\n")
            return .ok(lyrics: text, placed: lrc.count, total: lrc.count)
        }
        var raw = LyricsTiming.withoutTimecodes(lyrics).jsLines
        let joinedText = raw.joined(separator: "\n")
        let lines = lyricLines(joinedText)
        let parsed = ChordSheet.parse(joinedText)
        // Two sheet lines may be sung as one only when nothing but chords stands between them.
        let joinable: [Bool] = lines.indices.map { k in
            guard k + 1 < lines.count else { return false }
            for at in (lines[k].line + 1)..<lines[k + 1].line {
                if case .chords = parsed[at] { continue }
                if !ChordSheet.looseChordLine(raw[at]) { return false }
            }
            return true
        }
        let spans = LineAlign.alignSpans(
            lines.map(\.text), lrc.map { normalizeLine($0.text) },
            threshold: timecodeThreshold, joinable: joinable)
        for sp in spans {
            let at = lines[sp.i].line
            let indent = leadingWhitespace(raw[at])
            raw[at] = indent + LyricsTiming.format(lrc[sp.j].t) + " " + String(raw[at].dropFirst(indent.count))
        }
        return .ok(lyrics: raw.joined(separator: "\n"), placed: spans.reduce(0) { $0 + $1.nj }, total: lrc.count)
    }
}
