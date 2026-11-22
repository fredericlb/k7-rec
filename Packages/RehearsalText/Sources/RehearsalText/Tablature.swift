// Tablature.swift: ASCII guitar tab (`e|--0--2--|`) into systems of string lines.
// Ported from packages/tablature/src/tab.ts; a character's column is its x, so alignment IS the data.
// A line may hold several systems side by side and words after one ("x2"): each system comes out on its own,
// and the words stay on their string as its comment (docs/text.md).

import Foundation

public struct TabEvent: Equatable, Sendable {
    public enum Kind: Sendable { case fret, technique }
    public var col: Int
    public var text: String
    public var kind: Kind
}

public struct TabString: Equatable, Sendable {
    public var label: String
    public var events: [TabEvent]
}

public struct TabSystem: Equatable, Sendable {
    public var strings: [TabString]
    public var bars: [Int]
    public var cols: Int
    /// What followed each string's line in the text, "" when nothing did; one per string.
    public var comments: [String] = []
}

public enum TabNode: Equatable, Sendable {
    case empty
    case section(label: String)
    case text(String)
    case system(TabSystem)
}

public enum Tablature {
    static let label = Rx("^\\s*([A-Ga-g][#b]?)?\\s*")

    /// True if a line reads as one string of an ASCII tab (mostly dashes and frets), maybe several side by side.
    public static func looksLikeTabLine(_ line: String) -> Bool { row(line) != nil }

    static let bodyChars = Set("-|:0123456789hHpPbBrRsStTvVgGlLxXoO/\\~^()*.=<>".utf16)
    static let noteLetters = Set("ABCDEFGabcdefg".utf16)

    /// A line of tab as written: one piece per system side by side (label and body), each with the words that
    /// follow it up to the next piece. Nil when the line does not start with a piece. Whitespace ends a body.
    static func row(_ line: String) -> [(piece: String, comment: String)]? {
        let u = Array(line.utf16)
        func space(_ c: UInt16) -> Bool { c == 32 || c == 9 }
        func edge(_ k: Int) -> Bool { k >= u.count || space(u[k]) || u[k] == 45 || u[k] == 124 }
        func text(_ r: Range<Int>) -> String { String(utf16CodeUnits: Array(u[r]), count: r.count) }
        var out: [(piece: String, comment: String)] = []
        var i = 0
        while true {
            while i < u.count, space(u[i]) { i += 1 }
            guard i < u.count else { break }
            let start = i
            var j = i
            if noteLetters.contains(u[j]), edge(j + 1) || ((u[j + 1] == 35 || u[j + 1] == 98) && edge(j + 2)) {
                j += edge(j + 1) ? 1 : 2
                var gap = 0
                while j < u.count, space(u[j]), gap < 2 { j += 1; gap += 1 }
            }
            let bodyStart = j
            while j < u.count, bodyChars.contains(u[j]) { j += 1 }
            let dashes = u[bodyStart..<j].filter { $0 == 45 }.count
            if dashes >= 3, Double(dashes) / Double(max(j - bodyStart, 1)) >= 0.3 {
                out.append((text(start..<j), ""))
                i = j
                continue
            }
            guard !out.isEmpty else { return nil }
            // Not a piece: one word of the comment on the piece before it.
            var k = start
            while k < u.count, !space(u[k]) { k += 1 }
            let last = out.count - 1
            out[last].comment += (out[last].comment.isEmpty ? "" : " ") + text(start..<k)
            i = k
        }
        return out.isEmpty ? nil : out
    }

    // The label and where content starts, so a system's strings share one column grid.
    static func splitLabel(_ line: String) -> (label: String, bodyStart: Int) {
        let raw = label.first(in: line)?.text ?? ""
        return (raw.filter { !$0.isWhitespace }, raw.utf16Count)
    }

    static func isDigit(_ u: UInt16) -> Bool { u >= 48 && u <= 57 }

    static func parseStringLine(_ line: String, bodyStart: Int) -> (events: [TabEvent], bars: [Int]) {
        let units = Array(line.utf16)
        var events: [TabEvent] = []
        var bars: [Int] = []
        var i = bodyStart
        while i < units.count {
            let ch = units[i]
            let col = i - bodyStart
            if ch == 45 || ch == 32 {
                i += 1
            } else if ch == 124 {
                bars.append(col)
                i += 1
            } else if isDigit(ch) {
                var j = i + 1
                while j < units.count && isDigit(units[j]) { j += 1 }
                events.append(TabEvent(col: col, text: String(utf16CodeUnits: Array(units[i..<j]), count: j - i), kind: .fret))
                i = j
            } else {
                events.append(TabEvent(col: col, text: String(utf16CodeUnits: [ch], count: 1), kind: .technique))
                i += 1
            }
        }
        return (events, bars)
    }

    static func buildSystem(_ lines: [String]) -> TabSystem {
        let bodyStart = lines.map { splitLabel($0).bodyStart }.max() ?? 0
        var strings: [TabString] = []
        var bars = Set<Int>()
        var cols = 0
        for line in lines {
            let parsed = parseStringLine(line, bodyStart: bodyStart)
            strings.append(TabString(label: splitLabel(line).label, events: parsed.events))
            bars.formUnion(parsed.bars)
            cols = max(cols, line.utf16Count - bodyStart)
        }
        return TabSystem(strings: strings, bars: bars.sorted(), cols: cols)
    }

    /// Raw tab text into classified nodes; a SYSTEM is a run of consecutive string lines. Systems written side by
    /// side come out one after the other, left first; a line's trailing comment stays on its string.
    public static func parse(_ text: String) -> [TabNode] {
        var nodes: [TabNode] = []
        var run: [[(piece: String, comment: String)]] = []
        func flush() {
            let width = run.map(\.count).max() ?? 0
            for k in 0..<width {
                let rows = run.filter { k < $0.count }.map { $0[k] }
                var system = buildSystem(rows.map(\.piece))
                system.comments = rows.map(\.comment)
                nodes.append(.system(system))
            }
            run = []
        }
        for line in text.jsLines {
            if let r = row(line) {
                run.append(r)
                continue
            }
            flush()
            if line.jsTrimmed.isEmpty {
                nodes.append(.empty)
            } else if let b = ChordSheet.bracketSection.first(in: line), let l = b.group(1) {
                nodes.append(.section(label: l))
            } else if let c = ChordSheet.colonSection.first(in: line), let l = c.group(1) {
                nodes.append(.section(label: l))
            } else {
                nodes.append(.text(line))
            }
        }
        flush()
        return nodes
    }
}
