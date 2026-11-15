// LyricsTiming.swift: `{{MM:SS.cc}}` timecodes written IN a sheet's lines, and the line sung at a time.
// A timecode is not text: `strip` takes it off, with its one space, before any line is read.

import Foundation

/// A line index and the second it starts.
public struct LineTime: Equatable, Sendable {
    public var line: Int
    public var t: Double
    public init(line: Int, t: Double) {
        self.line = line
        self.t = t
    }
}

/// A timing stored BESIDE the text: the line index it had, its normalised text, and its seconds.
public struct StoredTiming: Equatable, Sendable {
    public var line: Int
    public var text: String
    public var t: Double
    public init(line: Int, text: String, t: Double) {
        self.line = line
        self.text = text
        self.t = t
    }
}

public enum LyricsTiming {
    static let codePattern = "\\{\\{\\s*([0-9]{1,3}):([0-5][0-9](?:\\.[0-9]{1,3})?)\\s*\\}\\}"
    static let code = Rx(codePattern)
    static let spacedCode = Rx(codePattern + " ?")
    static let trailingSpace = Rx("\\s+\\z")

    /// The line without its timecodes, which is what every reader but the player sees.
    public static func strip(_ line: String) -> String {
        trailingSpace.replacing(spacedCode.replacing(line, with: ""), with: "")
    }

    /// The first timecode on a line, in seconds, or nil.
    public static func timecode(of line: String) -> Double? {
        guard let m = code.first(in: line), let min = Double(m.group(1) ?? ""), let sec = Double(m.group(2) ?? "")
        else { return nil }
        return min * 60 + sec
    }

    /// `{{MM:SS.cc}}` for a time in seconds, to the hundredth, rounded down.
    public static func format(_ seconds: Double) -> String {
        let cs = seconds.isFinite ? Int(min(max(0, (seconds * 100 + 1e-6).rounded(.down)), 1e12)) : 0
        let s = cs / 100
        func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return "{{\(pad(s / 60)):\(pad(s % 60)).\(pad(cs % 100))}}"
    }

    /// Each timed line's start by line index, read off the codes in the text, in line order.
    public static func byLine(_ lyrics: String) -> [LineTime] {
        lyrics.jsLines.enumerated().compactMap { i, line in
            timecode(of: line).map { LineTime(line: i, t: $0) }
        }
    }

    /// The lyrics with every timecode taken off, every untimed line exactly as it was.
    public static func withoutTimecodes(_ lyrics: String) -> String {
        lyrics.jsLines.map { timecode(of: $0) == nil ? $0 : strip($0) }.joined(separator: "\n")
    }

    public static func hasTimecodes(_ lyrics: String) -> Bool { !byLine(lyrics).isEmpty }

    /// Stored timings laid onto the lyrics as they are now: an edited line loses its time.
    public static func fromStored(_ lyrics: String, _ timings: [StoredTiming]) -> [LineTime] {
        let lines = LRC.lyricLines(lyrics)
        let stored = timings.enumerated().sorted { ($0.element.line, $0.offset) < ($1.element.line, $1.offset) }
            .map(\.element)
        let pairs = LineAlign.alignLines(lines.map(\.text), stored.map(\.text), threshold: 1)
        return pairs.map { LineTime(line: lines[$0.0].line, t: stored[$0.1].t) }
    }

    /// The line being sung at `seconds`: the last one whose time has come, or nil before the first.
    public static func lineAt(_ byLine: [LineTime], seconds: Double) -> Int? {
        var best: Int?
        var bestT = -1.0
        for e in byLine where e.t <= seconds && e.t >= bestT {
            best = e.line
            bestT = e.t
        }
        return best
    }
}
