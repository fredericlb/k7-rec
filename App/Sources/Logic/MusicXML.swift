// What the score viewer reads off a sheet file: its kind, a MusicXML file as text (an .mxl unzipped),
// its parts, and the same file with one part kept. Pure, so it is tested without a view (docs/score.md).
import Compression
import Foundation

/// How a sheet is drawn, told by its file's extension: PDFKit, an image view, or the score view.
enum SheetKind: Equatable {
    case pdf, image, score

    static let scoreExtensions: Set<String> = ["musicxml", "mxl", "xml"]

    init(url: URL) {
        let ext = url.pathExtension.lowercased()
        self = ext == "pdf" ? .pdf : Self.scoreExtensions.contains(ext) ? .score : .image
    }
}

enum MusicXML {
    struct Part: Equatable { let id: String; let name: String }

    enum Failure: LocalizedError {
        case notAZip, brokenZip, method(Int), noScore, notText
        var errorDescription: String? {
            switch self {
            case .notAZip, .brokenZip: "This .mxl is not a readable archive."
            case .method(let m): "This .mxl is compressed with method \(m), which is not read."
            case .noScore: "This .mxl holds no score."
            case .notText: "This score is not UTF-8 text."
            }
        }
    }

    /// A score file's bytes as MusicXML text, compressed or not.
    static func text(of data: Data) throws -> String {
        if isZip(data) { return try unzipScore(Array(data)) }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw Failure.notText }
        return text
    }

    static func isZip(_ data: Data) -> Bool { data.count > 4 && data.prefix(4).elementsEqual([0x50, 0x4B, 3, 4]) }

    private static let scorePart = #"<score-part\b[^>]*\bid\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</score-part>"#
    private static let partGroup = #"<part-group\b[^>]*/>|<part-group\b[^>]*>[\s\S]*?</part-group>"#
    private static let partBody = #"<part\b[^>]*\bid\s*=\s*["']([^"']+)["'][^>]*>[\s\S]*?</part>"#

    /// Each part's id and name, in score order; a part with no name is "Part n".
    static func parts(of xml: String) -> [Part] {
        matches(scorePart, in: xml).enumerated().map { i, m in
            let raw = first(#"<part-name\b[^>]*>([\s\S]*?)</part-name>"#, in: m[2]) ?? ""
            let name = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            return Part(id: m[1], name: name.isEmpty ? "Part \(i + 1)" : name)
        }
    }

    /// The file with one part alone, by index into `parts(of:)`; an index out of range returns it whole.
    static func keepPart(_ xml: String, index: Int) -> String {
        let parts = parts(of: xml)
        guard parts.count > 1, parts.indices.contains(index) else { return xml }
        let kept = parts[index].id
        var out = replace(scorePart, in: xml) { $0[1] == kept ? $0[0] : "" }
        // A group bracket names parts that are gone; one part needs no bracket.
        out = replace(partGroup, in: out) { _ in "" }
        return replace(partBody, in: out) { $0[1] == kept ? $0[0] : "" }
    }

    // MARK: Regular expressions over the text

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants of this file; a typo is a crash in the tests, never at a user's.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func groups(_ m: NSTextCheckingResult, _ s: NSString) -> [String] {
        (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : s.substring(with: m.range(at: $0)) }
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        let s = text as NSString
        return regex(pattern).matches(in: text, range: NSRange(location: 0, length: s.length)).map { groups($0, s) }
    }

    private static func first(_ pattern: String, in text: String) -> String? { matches(pattern, in: text).first?[1] }

    private static func replace(_ pattern: String, in text: String, with make: ([String]) -> String) -> String {
        let s = text as NSString
        var out = "", last = 0
        for m in regex(pattern).matches(in: text, range: NSRange(location: 0, length: s.length)) {
            out += s.substring(with: NSRange(location: last, length: m.range.location - last)) + make(groups(m, s))
            last = m.range.location + m.range.length
        }
        return out + s.substring(from: last)
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: The .mxl archive

    private struct Entry { let method: Int; let size: Int; let unpacked: Int; let offset: Int }

    private static func u16(_ b: [UInt8], _ at: Int) -> Int { Int(b[at]) | Int(b[at + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ at: Int) -> Int { u16(b, at) | u16(b, at + 2) << 16 }

    /// The central directory's entries by name; the end record is the last 22 bytes before an optional comment.
    private static func entries(_ b: [UInt8]) throws -> [String: Entry] {
        var end = b.count - 22
        while end >= 0, u32(b, end) != 0x0605_4B50 { end -= 1 }
        guard end >= 0 else { throw Failure.notAZip }
        var out: [String: Entry] = [:]
        var at = u32(b, end + 16)
        for _ in 0..<u16(b, end + 10) {
            guard at + 46 <= b.count, u32(b, at) == 0x0201_4B50 else { throw Failure.brokenZip }
            let nameLength = u16(b, at + 28)
            guard at + 46 + nameLength <= b.count else { throw Failure.brokenZip }
            let name = String(decoding: b[(at + 46)..<(at + 46 + nameLength)], as: UTF8.self)
            out[name] = Entry(method: u16(b, at + 10), size: u32(b, at + 20), unpacked: u32(b, at + 24), offset: u32(b, at + 42))
            at += 46 + nameLength + u16(b, at + 30) + u16(b, at + 32)
        }
        return out
    }

    private static func read(_ b: [UInt8], _ e: Entry) throws -> String {
        guard e.offset + 30 <= b.count else { throw Failure.brokenZip }
        let start = e.offset + 30 + u16(b, e.offset + 26) + u16(b, e.offset + 28)
        guard start + e.size <= b.count else { throw Failure.brokenZip }
        let raw = Array(b[start..<(start + e.size)])
        switch e.method {
        case 0: return String(decoding: raw, as: UTF8.self)
        case 8: return String(decoding: try inflate(raw, size: e.unpacked), as: UTF8.self)
        default: throw Failure.method(e.method)
        }
    }

    /// Raw DEFLATE, which is what `COMPRESSION_ZLIB` decodes; the directory gives the unpacked size.
    private static func inflate(_ raw: [UInt8], size: Int) throws -> [UInt8] {
        guard size > 0 else { return [] }
        var out = [UInt8](repeating: 0, count: size)
        let n = compression_decode_buffer(&out, size, raw, raw.count, nil, COMPRESSION_ZLIB)
        guard n == size else { throw Failure.brokenZip }
        return out
    }

    /// The score an .mxl names in META-INF/container.xml, else its one .musicxml or .xml outside META-INF.
    private static func unzipScore(_ b: [UInt8]) throws -> String {
        let files = try entries(b)
        let root = try files["META-INF/container.xml"].flatMap {
            first(#"<rootfile\b[^>]*\bfull-path\s*=\s*["']([^"']+)["']"#, in: try read(b, $0))
        }
        let name = root ?? files.keys.sorted().first {
            !$0.hasPrefix("META-INF/") && ["musicxml", "xml"].contains(($0 as NSString).pathExtension.lowercased())
        }
        guard let name, let entry = files[name] else { throw Failure.noScore }
        return try read(b, entry)
    }
}
