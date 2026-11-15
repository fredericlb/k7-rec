// Turns picked media items into song rows: readable ones are exported into Songs/, the others become references.
// What a reader gets wrong: the folder and the uuid come from the item's id, so picking an item twice replaces its copy.
import Foundation
import RehearsalStore

/// Copies an item's audio to `destination` as m4a; the real one is Live/AssetExporter.
protocol AudioExporting: Sendable {
    func export(from source: URL, to destination: URL, progress: @Sendable (Double) -> Void) async throws
}

struct AppleMusicOutcome: Equatable {
    var exported = 0, referenced = 0, skipped: [String] = [], cancelled = false

    var message: String {
        var parts: [String] = []
        if exported > 0 { parts.append("\(exported) imported as files") }
        if referenced > 0 { parts.append("\(referenced) added as references (streaming only)") }
        parts += skipped
        if cancelled { parts.append("Cancelled.") }
        return parts.joined(separator: "\n")
    }
}

struct AppleMusicWriter: Sendable {
    let store: Store
    let songs: URL
    let exporter: AudioExporting

    /// Writes every item; `progress` gets the item's index and its fraction. Stops at cancellation, keeping what is done.
    func write(_ items: [any MediaItemInfo], progress: @Sendable (Int, Double) -> Void) async -> AppleMusicOutcome {
        var out = AppleMusicOutcome()
        for (i, item) in items.enumerated() {
            if Task.isCancelled { out.cancelled = true; break }
            progress(i, 0)
            do {
                switch AppleMusic.plan(for: item) {
                case .skip(let why): out.skipped.append(why)
                case .reference(let id):
                    let old = try await known(item)
                    let row = AppleMusic.row(
                        for: item, plan: .reference(storeID: id), id: old?.id ?? newID(), createdAt: old?.createdAt ?? Date().timeIntervalSince1970,
                        folder: Self.folder(of: old, item))
                    try await put(row, file: nil)
                    out.referenced += 1
                case .exportFile:
                    try await export(item) { progress(i, $0) }
                    out.exported += 1
                }
            } catch is CancellationError { out.cancelled = true; break } catch {
                out.skipped.append("\(AppleMusic.label(item)): \(error.localizedDescription)")
            }
        }
        return out
    }

    private func known(_ item: some MediaItemInfo) async throws -> RehearsalStore.Song? {
        try await store.list(Query<RehearsalStore.Song>(where: [Filter("uuid", equals: .text(AppleMusic.uuid(of: item)))])).first
    }

    private func export(_ item: some MediaItemInfo, progress: @Sendable (Double) -> Void) async throws {
        guard let source = item.assetURL else { return }
        let old = try await known(item)
        let name = Self.folder(of: old, item)
        let dir = songs.appendingPathComponent(name, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: songs, withIntermediateDirectories: true)
        // The export lands in a temp folder and replaces the old copy whole, so a failed one keeps the song as it was.
        let tmp = songs.appendingPathComponent(".importing-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        try await exporter.export(from: source, to: tmp.appendingPathComponent("original.m4a"), progress: progress)
        if fm.fileExists(atPath: dir.path) {
            try SongImporter.carryOver(from: dir, to: tmp)
            _ = try fm.replaceItemAt(dir, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: dir)
        }
        let row = AppleMusic.row(for: item, plan: .exportFile, id: old?.id ?? newID(), createdAt: old?.createdAt ?? Date().timeIntervalSince1970, folder: name)
        let file = SongFile(id: "\(row.id):original.m4a", songId: row.id, kind: .audio, path: "\(name)/original.m4a", name: "original.m4a", mime: "audio/mp4")
        try await put(row, file: file)
    }

    private static func folder(of old: RehearsalStore.Song?, _ item: some MediaItemInfo) -> String {
        if let known = old?.folder, !known.isEmpty { return known }
        return AppleMusic.folderName(for: item)
    }

    private func put(_ row: RehearsalStore.Song, file: SongFile?) async throws {
        try await store.write { tx in
            var row = row
            if let old = try tx.get(RehearsalStore.Song.self, row.id) { row.tags = old.tags }
            try tx.put(row)
            for f in try tx.list(Query<SongFile>(where: [Filter("songId", equals: .text(row.id)), Filter("kind", equals: .text("audio"))])) { try tx.delete(SongFile.self, f.id) }
            if let file { try tx.put(file) }
        }
    }
}
