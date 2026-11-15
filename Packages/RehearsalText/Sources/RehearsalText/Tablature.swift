// Tablature.swift: ASCII guitar tab (`e|--0--2--|`) into systems of string lines.
// Ported from packages/tablature/src/tab.ts; a character's column is its x, so alignment IS the data.

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
}

public enum TabNode: Equatable, Sendable {
    case empty
    case section(label: String)
    case text(String)
    case system(TabSystem)
}

public enum Tablature {
    static let body = Rx("^[\\-|0-9\\shHpPbBrRsStTvVgGlLxXoO/\\\\~^()*.=<>]+\\z")
    static let label = Rx("^\\s*([A-Ga-g][#b]?)?\\s*")

    /// True if a line reads as one string of an ASCII tab (mostly dashes and frets).
    public static func looksLikeTabLine(_ line: String) -> Bool {
        let rest = label.replacing(line, with: "")
        if !body.test(rest) { return false }
        let nonSpace = rest.filter { !$0.isWhitespace }.utf16Count
        let dashes = rest.reduce(0) { $1 == "-" ? $0 + 1 : $0 }
        return dashes >= 3 && Double(dashes) / Double(max(nonSpace, 1)) >= 0.3
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

    /// Raw tab text into classified nodes; a SYSTEM is a run of consecutive string lines.
    public static func parse(_ text: String) -> [TabNode] {
        var nodes: [TabNode] = []
        var run: [String] = []
        func flush() {
            if !run.isEmpty { nodes.append(.system(buildSystem(run))) }
            run = []
        }
        for line in text.jsLines {
            if looksLikeTabLine(line) {
                run.append(line)
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
