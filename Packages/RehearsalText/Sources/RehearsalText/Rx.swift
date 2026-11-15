// Rx.swift: a thin NSRegularExpression wrapper over UTF-16 offsets, as the TS regexes index.
// Patterns are written ASCII-explicit ([0-9], \z) because ICU's \d and $ differ from JS's.

import Foundation

struct RxMatch {
    let source: NSString
    let range: NSRange
    let groups: [NSRange]

    var start: Int { range.location }
    var end: Int { range.location + range.length }
    var text: String { source.substring(with: range) }

    func group(_ n: Int) -> String? {
        guard n < groups.count, groups[n].location != NSNotFound else { return nil }
        return source.substring(with: groups[n])
    }
}

struct Rx: Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, ignoreCase: Bool = false, multiline: Bool = false) {
        var options: NSRegularExpression.Options = []
        if ignoreCase { options.insert(.caseInsensitive) }
        if multiline { options.insert(.anchorsMatchLines) }
        guard let built = try? NSRegularExpression(pattern: pattern, options: options) else {
            preconditionFailure("bad pattern \(pattern)")
        }
        regex = built
    }

    private func wrap(_ r: NSTextCheckingResult, _ ns: NSString) -> RxMatch {
        RxMatch(source: ns, range: r.range, groups: (0..<r.numberOfRanges).map { r.range(at: $0) })
    }

    func first(in s: String) -> RxMatch? {
        let ns = s as NSString
        return regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)).map { wrap($0, ns) }
    }

    func all(in s: String) -> [RxMatch] {
        let ns = s as NSString
        return regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { wrap($0, ns) }
    }

    func test(_ s: String) -> Bool { first(in: s) != nil }

    func replacing(_ s: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    func split(_ s: String) -> [String] {
        let ns = s as NSString
        var out: [String] = []
        var at = 0
        for m in all(in: s) {
            out.append(ns.substring(with: NSRange(location: at, length: m.start - at)))
            at = m.end
        }
        out.append(ns.substring(from: at))
        return out
    }
}

extension String {
    var utf16Count: Int { utf16.count }

    // JS `trim()`: whitespace and line terminators at both ends.
    var jsTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    // JS `split(/\r?\n/)`; a Character-based split would see "\r\n" as one grapheme.
    var jsLines: [String] { Rx.newline.split(self) }
}

extension Rx {
    static let newline = Rx("\\r?\\n")
    static let whitespaceRun = Rx("\\s+")
}

// JS `split(/\s+/)` on a trimmed string: an empty string gives one empty token.
func splitWhitespace(_ s: String) -> [String] { Rx.whitespaceRun.split(s.jsTrimmed) }

func leadingWhitespace(_ s: String) -> String {
    String(s.prefix(while: { $0.isWhitespace }))
}
