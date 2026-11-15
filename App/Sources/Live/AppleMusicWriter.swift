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
                    let row = AppleMusic.row(for: item, plan: .reference(storeID: id), id: old?.id ?? newID(), createdAt: old?.createdAt ?? Date().timeIntervalSince1970)
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
        let name = SongImporter.safe(item.title.isEmpty ? "Untitled" : item.title) + " " + String(item.itemID.suffix(8))
        let dir = songs.appendingPathComponent(name, isDirectory: true)
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        do { try await exporter.export(from: source, to: dir.appendingPathComponent("original.m4a"), progress: progress) } catch {
            try? fm.removeItem(at: dir)
            throw error
        }
        let row = AppleMusic.row(for: item, plan: .exportFile, id: old?.id ?? newID(), createdAt: old?.createdAt ?? Date().timeIntervalSince1970)
        let file = SongFile(id: "\(row.id):original.m4a", songId: row.id, kind: .audio, path: "\(name)/original.m4a", name: "original.m4a", mime: "audio/mp4")
        try await put(row, file: file)
    }

    private func put(_ row: RehearsalStore.Song, file: SongFile?) async throws {
        try await store.write { tx in
            try tx.put(row)
            for f in try tx.list(Query<SongFile>(where: [Filter("songId", equals: .text(row.id)), Filter("kind", equals: .text("audio"))])) { try tx.delete(SongFile.self, f.id) }
            if let file { try tx.put(file) }
        }
    }
}
