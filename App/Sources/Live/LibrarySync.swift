// Mirrors the library's rows as one JSON per song and per take, and rebuilds rows from the JSONs other devices wrote.
// What a reader gets wrong: three versions are compared (rows now, file now, file as last synced), never two (docs/sync.md).
import CryptoKit
import Foundation
import RehearsalStore

struct SongRecord: Codable, Equatable {
    var song: RehearsalStore.Song
    var files: [SongFile]
}

/// What a pass saw: the records it changed here, the ones on disk, the ones still in iCloud.
struct SyncReport: Equatable {
    var changed: [String] = []
    var records = 0
    var pending = 0
}

struct TakeRecord: Codable, Equatable {
    var take: RehearsalStore.Take
    var moments: [Moment]
    var markers: [Marker]
}

// UserDefaults is documented thread-safe.
struct LibrarySync: @unchecked Sendable {
    let store: Store
    let records: URL
    let defaults: UserDefaults
    private let key = "librarySync.synced"
    /// A record deleted on a device is announced by `<record>.deleted`; a missing record is never read as a deletion.
    static let tombstone = ".deleted"

    init(store: Store, records: URL, defaults: UserDefaults = .standard) {
        (self.store, self.records, self.defaults) = (store, records, defaults)
    }

    /// One pass; a pass that cannot read the rows or the folder changes nothing.
    @discardableResult
    func run() async -> SyncReport {
        let fm = FileManager.default
        try? fm.createDirectory(at: records, withIntermediateDirectories: true)
        guard let local = try? await snapshot(), let listing = remote() else { return SyncReport() }
        var synced = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        var changed: [String] = []
        let names = Set(local.keys).union(listing.files.keys).union(listing.deleted).subtracting(listing.pending)
        for name in names {
            let (l, r, s) = (local[name], listing.files[name], synced[name])
            let (lh, rh) = (l.map(Self.hash), r.map(Self.hash))
            if listing.deleted.contains(name) {
                // A tombstone is a deletion somebody chose: the rows go, the file with them.
                if l != nil { await remove(name); changed.append(name) }
                if r != nil { discard(name) }
                synced[name] = nil
                continue
            }
            // Nothing is ever deleted because something is missing: a missing file is written again, missing rows are rebuilt.
            switch (l, r) {
            case let (l?, nil):
                if write(l, name) { synced[name] = lh }
            case let (nil, r?):
                if await apply(name, r) { synced[name] = rh; changed.append(name) }
            case let (l?, r?):
                if lh == rh { synced[name] = rh } else if s != rh {
                    if await apply(name, r) { synced[name] = rh; changed.append(name) }
                } else if write(l, name) { synced[name] = lh }
            default: break
            }
        }
        defaults.set(synced, forKey: key)
        return SyncReport(changed: changed, records: listing.files.count, pending: listing.pending.count)
    }

    // MARK: rows to records

    /// Every record the rows make now, by file name, encoded the same way every time.
    func snapshot() async throws -> [String: Data] {
        let songs = try await store.list(Query<RehearsalStore.Song>())
        let files = Dictionary(grouping: try await store.list(Query<SongFile>(orderBy: "position")), by: \.songId)
        let takes = try await store.list(Query<RehearsalStore.Take>())
        let moments = Dictionary(grouping: try await store.list(Query<Moment>(orderBy: "startSec")), by: \.recordingPath)
        let markers = Dictionary(grouping: try await store.list(Query<Marker>(orderBy: "atSec")), by: \.recordingPath)
        var out: [String: Data] = [:]
        for s in songs { out["song-\(s.id).json"] = try Self.encode(SongRecord(song: s, files: files[s.id] ?? [])) }
        for t in takes {
            let own = moments[t.audioPath] ?? [], pins = markers[t.audioPath] ?? []
            out["take-\(t.id).json"] = try Self.encode(TakeRecord(take: t, moments: own, markers: pins))
        }
        return out
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    // MARK: records to rows

    /// True when the rows now hold the record; a record that does not decode, or a write that fails, is not applied.
    private func apply(_ name: String, _ data: Data) async -> Bool {
        let decoder = JSONDecoder()
        if name.hasPrefix("song-"), let r = try? decoder.decode(SongRecord.self, from: data) {
            return (try? await store.saveSong(r.song, files: r.files)) != nil
        } else if name.hasPrefix("take-"), let r = try? decoder.decode(TakeRecord.self, from: data) {
            let path = r.take.audioPath
            return (try? await store.write { tx -> Bool in
                if !path.isEmpty {
                    let named = Filter("recordingPath", equals: .text(path))
                    for m in try tx.list(Query<Moment>(where: [named])) { try tx.delete(Moment.self, m.id) }
                    for k in try tx.list(Query<Marker>(where: [named])) { try tx.delete(Marker.self, k.id) }
                }
                try tx.put(r.take)
                for m in r.moments { try tx.put(m) }
                for k in r.markers { try tx.put(k) }
                return true
            }) == true
        }
        return false
    }

    /// Announces a deletion the user made here: a tombstone for the other devices, and the record's file goes.
    func markDeleted(_ name: String) {
        _ = write(Data("deleted".utf8), name + Self.tombstone)
        discard(name)
        var synced = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        synced[name] = nil
        defaults.set(synced, forKey: key)
    }

    private func remove(_ name: String) async {
        let id = String(name.drop { $0 != "-" }.dropFirst().dropLast(".json".count))
        if name.hasPrefix("song-") { try? await store.deleteSong(id) } else if name.hasPrefix("take-") { try? await store.deleteTakeWithMoments(id) }
    }

    // MARK: the folder

    /// Writes through a file coordinator, as iCloud expects; false when the file could not be written.
    private func write(_ data: Data, _ name: String) -> Bool {
        var wrote = false
        var failure: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: records.appendingPathComponent(name), options: .forReplacing, error: &failure) { url in
            wrote = (try? data.write(to: url, options: .atomic)) != nil
        }
        return wrote && failure == nil
    }

    /// The records on disk; a name whose content is still in iCloud is `pending` and left out of the pass, and asked for.
    private func remote() -> (files: [String: Data], pending: Set<String>, deleted: Set<String>)? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: records.path) else { return nil }
        var files: [String: Data] = [:], pending: Set<String> = [], deleted: Set<String> = []
        for name in names {
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let real = String(name.dropFirst().dropLast(".icloud".count))
                pending.insert(real.hasSuffix(Self.tombstone) ? String(real.dropLast(Self.tombstone.count)) : real)
                try? fm.startDownloadingUbiquitousItem(at: records.appendingPathComponent(real))
            } else if name.hasSuffix(Self.tombstone) {
                deleted.insert(String(name.dropLast(Self.tombstone.count)))
            } else if name.hasSuffix(".json"), let data = try? Data(contentsOf: records.appendingPathComponent(name)) {
                files[name] = data
            } else if name.hasSuffix(".json") { pending.insert(name) }
        }
        return (files, pending, deleted)
    }

    /// Removes a record's file, through a coordinator.
    private func discard(_ name: String) {
        var failure: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: records.appendingPathComponent(name), options: .forDeleting, error: &failure) { url in
            try? FileManager.default.removeItem(at: url)
        }
    }
}
