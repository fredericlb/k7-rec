// Copies picked folders and audio files into the app's Songs folder and files them in the store.
// What a reader gets wrong: a folder re-imports onto itself (same destination, same id), it never doubles.
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
        let name = Self.safe(isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent)
        let dest = songs.appendingPathComponent(name, isDirectory: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        if isFolder {
            try fm.copyItem(at: url, to: dest)
        } else {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: dest.appendingPathComponent("original." + url.pathExtension.lowercased()))
        }
        var (song, files) = try SongFolder.read(dest, destination: name)
        if !isFolder { (song.title, song.artist) = await Self.tags(of: url, fallback: song.title) }
        guard !files.isEmpty else { try? fm.removeItem(at: dest); throw ImportError.nothingToImport }
        let (filed, rows) = (song, files)
        try await store.write { tx in
            if let old = try tx.get(RehearsalStore.Song.self, filed.id) { var kept = filed; kept.createdAt = old.createdAt; try tx.put(kept) } else { try tx.put(filed) }
            for f in try tx.list(Query<SongFile>(where: [Filter("songId", equals: .text(filed.id))])) { try tx.delete(SongFile.self, f.id) }
            for f in rows { try tx.put(f) }
        }
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
