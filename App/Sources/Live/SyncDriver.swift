// Runs LibrarySync when the rows change, when iCloud delivers a file, and when the app comes back.
// What a reader gets wrong: rows are watched without their envelopes, which never change after a save.
import Foundation
import Observation
import RehearsalStore

@Observable @MainActor
final class SyncDriver {
    /// Whether the files are in the iCloud container, or on this device only.
    let inCloud: Bool
    private(set) var report: SyncReport?
    private(set) var lastRun: Date?
    private(set) var running = false
    /// Counts what iCloud delivered or changed in the container, so a screen showing a file reads it again.
    private(set) var deliveries = 0
    @ObservationIgnored private let sync: LibrarySync
    @ObservationIgnored private let roots: [URL]
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    init(store: Store, paths: AppPaths) {
        sync = LibrarySync(store: store, records: paths.records)
        inCloud = paths.cloud != nil
        roots = [paths.songs, paths.takes, paths.records]
        watch(store.observe(Query<RehearsalStore.Song>()))
        watch(store.observe(Query<SongFile>()))
        watch(store.observe(Query<RehearsalStore.Take>(fields: ["id", "songId", "title", "createdAt", "duration", "gain", "audioPath"])))
        watch(store.observe(Query<Moment>(fields: ["id", "recordingPath", "startSec", "endSec", "text", "tags", "validated", "clipPath"])))
        watch(store.observe(Query<Marker>()))
        if paths.cloud != nil { listen() }
        schedule()
    }

    // The driver lives as long as the app, so the query and its observers are never torn down.
    deinit { tasks.forEach { $0.cancel() } }

    /// A pass soon, however many changes asked for one meanwhile.
    func schedule(after seconds: Double = 1.5) {
        pending?.cancel()
        pending = Task { [weak self, sync, roots] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.running = true
            let done = await sync.run()
            Self.download(roots)
            self?.report = done
            self?.lastRun = Date()
            self?.running = false
        }
    }

    /// A take the user deleted here: the other devices are told, then a pass runs.
    func deleted(takeID: String) {
        sync.markDeleted("take-\(takeID).json")
        schedule()
    }

    private func watch<D: Document>(_ stream: AsyncThrowingStream<[D], Error>) {
        tasks.append(Task { [weak self] in
            do { for try await _ in stream { self?.schedule() } } catch {}
        })
    }

    /// iCloud delivering or changing a file, a record or a song's audio, asks for a pass.
    private func listen() {
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.deliveries += 1; self?.schedule() }
            })
        }
        q.start()
        query = q
    }

    /// Every file still only in iCloud is asked for, so a song or a take plays when it is tapped (docs/sync.md).
    nonisolated static func download(_ roots: [URL]) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        for root in roots {
            guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { continue }
            for case let url as URL in walk {
                if let real = placeholderTarget(url) { try? fm.startDownloadingUbiquitousItem(at: real); continue }
                guard let v = try? url.resourceValues(forKeys: keys), v.isUbiquitousItem == true,
                      v.ubiquitousItemDownloadingStatus != .current else { continue }
                try? fm.startDownloadingUbiquitousItem(at: url)
            }
        }
    }

    /// The file a `.name.icloud` placeholder stands for, nil for any other name.
    nonisolated static func placeholderTarget(_ url: URL) -> URL? {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), url.pathExtension == "icloud", name.count > ".icloud".count + 1 else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
    }
}
