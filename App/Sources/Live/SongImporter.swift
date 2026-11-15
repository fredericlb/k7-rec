// Copies picked folders and audio files into the app's Songs folder and files them in the store.
// What a reader gets wrong: the copy, not the source, carries the uuid (docs/app.md); a re-import reuses it.
import AVFoundation
import Foundation
import RehearsalStore

struct SongImporter: Sendable {
    let store: Store
    let songs: URL

    /// Imports each URL; returns one message per URL that failed.
    func importURLs(_ urls: [URL]) async -> [String] {
        var failures: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { try await importOne(url) } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return failures
    }

    private func importOne(_ url: URL) async throws {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let fm = FileManager.default
        try fm.createDirectory(at: songs, withIntermediateDirectories: true)
        let picked = Self.safe(isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent)
        let tail = SongFolder.destinationName(for: url).suffix(8)
        let name = isFolder ? Self.safe(SongFolder.destinationName(for: url)) : "\(picked) \(tail)"
        let dest = songs.appendingPathComponent(name, isDirectory: true)
        let known = (try? SongFolder.read(dest, destination: name))?.song.uuid ?? ""
        let tmp = songs.appendingPathComponent(".importing-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }
        if isFolder {
            try fm.copyItem(at: url, to: tmp)
        } else {
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: tmp.appendingPathComponent("original." + url.pathExtension.lowercased()))
        }
        if fm.fileExists(atPath: dest.path) { try Self.carryOver(from: dest, to: tmp) }
        var (song, files) = try SongFolder.read(tmp, destination: name)
        guard !files.isEmpty else { throw ImportError.nothingToImport }
        if song.uuid.isEmpty {
            try Self.stamp(uuid: known.isEmpty ? UUID().uuidString.lowercased() : known, in: tmp)
            (song, files) = try SongFolder.read(tmp, destination: name)
        }
        if song.title == name { song.title = picked }
        if !isFolder { (song.title, song.artist) = await Self.tags(of: url, fallback: picked) }
        if fm.fileExists(atPath: dest.path) { _ = try fm.replaceItemAt(dest, withItemAt: tmp) } else { try fm.moveItem(at: tmp, to: dest) }
        let (filed, rows) = (song, files)
        try await store.write { tx in
            if let old = try tx.get(RehearsalStore.Song.self, filed.id) {
                var kept = filed
                kept.createdAt = old.createdAt
                if kept.tags.isEmpty { kept.tags = old.tags }
                try tx.put(kept)
            } else { try tx.put(filed) }
            for f in try tx.list(Query<SongFile>(where: [Filter("songId", equals: .text(filed.id))])) { try tx.delete(SongFile.self, f.id) }
            for f in rows { try tx.put(f) }
        }
    }

    /// Copies what the app made in `old` (texts, sheets) into `fresh` where the source brought no file of that name.
    static func carryOver(from old: URL, to fresh: URL) throws {
        let fm = FileManager.default
        for file in ["lyrics.txt", "chords.txt", "tabs.txt"] {
            let (from, to) = (old.appendingPathComponent(file), fresh.appendingPathComponent(file))
            if fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) { try fm.copyItem(at: from, to: to) }
        }
        let sheets = old.appendingPathComponent("sheets", isDirectory: true)
        let names = ((try? fm.contentsOfDirectory(atPath: sheets.path)) ?? []).filter { !$0.hasPrefix(".") }
        guard !names.isEmpty else { return }
        let target = fresh.appendingPathComponent("sheets", isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for name in names where !fm.fileExists(atPath: target.appendingPathComponent(name).path) {
            try fm.copyItem(at: sheets.appendingPathComponent(name), to: target.appendingPathComponent(name))
        }
    }

    /// Writes `uuid` into the copy's song.yaml, creating it when absent; the source is never touched.
    static func stamp(uuid: String, in folder: URL) throws {
        let yaml = folder.appendingPathComponent("song.yaml")
        let old = (try? String(contentsOf: yaml, encoding: .utf8)) ?? ""
        var lines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.hasPrefix("uuid:") }
        var at = 0
        // The uuid goes after a leading document marker, so the file stays one YAML document.
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "---" || t.hasPrefix("--- ") { at = i + 1; break }
            if !(t.isEmpty || t.hasPrefix("#") || t.hasPrefix("%")) { break }
        }
        lines.insert("uuid: \(uuid)", at: at)
        try lines.joined(separator: "\n").write(to: yaml, atomically: true, encoding: .utf8)
    }

    /// A song named by its tags, or by `fallback` (the file name) when it has none.
    static func tags(of url: URL, fallback: String) async -> (String, String) {
        let items = (try? await AVURLAsset(url: url).load(.commonMetadata)) ?? []
        func value(_ id: AVMetadataIdentifier) async -> String {
            guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first else { return "" }
            return ((try? await item.load(.stringValue)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title = await value(.commonIdentifierTitle)
        return (title.isEmpty ? fallback : title, await value(.commonIdentifierArtist))
    }

    static func safe(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "[/:\\\\]", with: "-", options: .regularExpression)
        return cleaned.isEmpty ? "Song" : cleaned
    }
}

enum ImportError: LocalizedError {
    case nothingToImport
    var errorDescription: String? { "no audio, lyrics, chords, tabs or sheets found" }
}
