// SongFolder.swift — reads a song folder (`song.yaml` and the files beside it) into a Song and its SongFiles.
// What a reader gets wrong: only uuid, title, artist, tags and the sheets' order are read; the rest is left alone.

import Foundation
import Yams

public enum SongFolder {
    private static let audioExtensions: Set<String> = ["flac", "wav", "mp3", "m4a", "aac", "aif", "aiff", "ogg", "opus"]
    private static let texts: [(String, SongFileKind)] = [("lyrics.txt", .lyrics), ("chords.txt", .chords), ("tabs.txt", .tabs)]

    /// Reads `folder`; file paths are `destination/<file>`, the place the app copies the folder to.
    public static func read(_ folder: URL, destination: String? = nil) throws -> (song: Song, files: [SongFile]) {
        let fm = FileManager.default
        let dest = destination ?? folder.lastPathComponent
        let yaml = folder.appendingPathComponent("song.yaml")
        let meta = (try? String(contentsOf: yaml, encoding: .utf8)).flatMap { try? Yams.load(yaml: $0) } as? [String: Any] ?? [:]

        let uuid = text(meta["uuid"])
        let song = Song(
            id: uuid.isEmpty ? newID() : uuid, uuid: uuid,
            title: text(meta["title"]).nonEmpty ?? folder.lastPathComponent, artist: text(meta["artist"]),
            tags: (meta["tags"] as? [Any])?.map(text).filter { !$0.isEmpty } ?? [])

        func exists(_ rel: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(rel).path) }
        var files: [SongFile] = []
        func add(_ kind: SongFileKind, _ rel: String, name: String, mime: String = "") {
            files.append(SongFile(id: "\(song.id):\(rel)", songId: song.id, kind: kind, path: "\(dest)/\(rel)",
                                  name: name, mime: mime, position: files.count))
        }

        if let master = try fm.contentsOfDirectory(atPath: folder.path).sorted().first(where: {
            let u = URL(fileURLWithPath: $0)
            return audioExtensions.contains(u.pathExtension.lowercased()) && u.deletingPathExtension().lastPathComponent == "original"
        }) { add(.audio, master, name: "original") }
        for (file, kind) in texts where exists(file) { add(kind, file, name: file) }
        for sheet in try sheets(folder, meta) { add(.sheet, sheet.file, name: sheet.name, mime: sheet.mime) }
        return (song, files)
    }

    /// The sidecar's sheets in its order, then any other file under `sheets/`, by name.
    private static func sheets(_ folder: URL, _ meta: [String: Any]) throws -> [(file: String, name: String, mime: String)] {
        let fm = FileManager.default
        let listed = ((meta["songbook"] as? [String: Any])?["sheets"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        var out: [(file: String, name: String, mime: String)] = []
        for s in listed {
            let file = text(s["file"])
            guard !file.isEmpty, !file.contains(".."), fm.fileExists(atPath: folder.appendingPathComponent(file).path) else { continue }
            out.append((file, text(s["name"]).nonEmpty ?? URL(fileURLWithPath: file).lastPathComponent, text(s["mime"])))
        }
        let dir = folder.appendingPathComponent("sheets")
        for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where !name.hasPrefix(".") {
            if !out.contains(where: { $0.file == "sheets/\(name)" }) { out.append(("sheets/\(name)", name, "")) }
        }
        return out
    }

    private static func text(_ v: Any?) -> String {
        switch v {
        case let s as String: s.trimmingCharacters(in: .whitespacesAndNewlines)
        case let n as NSNumber: n.stringValue
        default: ""
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
