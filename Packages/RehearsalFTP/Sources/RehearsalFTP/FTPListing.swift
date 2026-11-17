// FTPListing.swift: reads a folder listing, the machine-readable MLSD or the Unix and DOS styles of LIST.
// What a reader gets wrong: LIST has no standard, so a line that matches no style is skipped, never an error.

import Foundation

public enum FTPListing {
  /// "type=file;size=12;modify=...; name" lines; the current and parent folders are left out.
  public static func parseMLSD(_ text: String) -> [FTPEntry] {
    lines(text).compactMap { line in
      guard let space = line.firstIndex(of: " ") else { return nil }
      let facts = line[..<space].split(separator: ";").reduce(into: [String: String]()) { out, fact in
        let kv = fact.split(separator: "=", maxSplits: 1)
        if kv.count == 2 { out[kv[0].lowercased()] = String(kv[1]) }
      }
      let name = String(line[line.index(after: space)...])
      switch facts["type"]?.lowercased() {
      case "file": return FTPEntry(name: name, isDirectory: false, size: facts["size"].flatMap { Int64($0) })
      case "dir": return FTPEntry(name: name, isDirectory: true)
      default: return nil
      }
    }
  }

  /// Unix `ls -l` lines and the DOS `MM-DD-YY 10:00AM <DIR>` style.
  public static func parseList(_ text: String) -> [FTPEntry] {
    lines(text).compactMap { line in
      if let m = unix.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let kind = range(m, 1, line), let size = range(m, 2, line), let name = range(m, 3, line) {
        let clean = name.components(separatedBy: " -> ")[0]
        guard clean != ".", clean != ".." else { return nil }
        return FTPEntry(name: clean, isDirectory: kind == "d", size: Int64(size))
      }
      if let m = dos.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let size = range(m, 1, line), let name = range(m, 2, line) {
        return FTPEntry(name: name, isDirectory: size == "<DIR>", size: Int64(size))
      }
      return nil
    }
  }

  private static func lines(_ text: String) -> [String] {
    text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }.filter { !$0.isEmpty }
  }

  private static func range(_ m: NSTextCheckingResult, _ i: Int, _ line: String) -> String? {
    Range(m.range(at: i), in: line).map { String(line[$0]) }
  }

  private static let unix = try! NSRegularExpression(
    pattern: #"^([\-dlbcps])[rwxsStT\-]{9}[@+.]?\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\w{3}\s+\d{1,2}\s+(?:\d{4}|\d{1,2}:\d{2})\s+(.+)$"#)
  private static let dos = try! NSRegularExpression(pattern: #"^\d\d-\d\d-\d\d\s+\d\d:\d\d[AP]M\s+(<DIR>|\d+)\s+(.+)$"#)
}
