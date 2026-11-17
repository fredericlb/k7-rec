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

    /// iCloud delivering or changing a file asks for a pass.
    private func listen() {
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
        q.start()
        query = q
    }

    /// Every file still only in iCloud is asked for, so a take plays when it is tapped.
    nonisolated static func download(_ roots: [URL]) {
        let fm = FileManager.default
        for root in roots {
            guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walk where url.lastPathComponent.hasPrefix(".") && url.pathExtension == "icloud" {
                let real = url.deletingLastPathComponent().appendingPathComponent(String(url.lastPathComponent.dropFirst().dropLast(".icloud".count)))
                try? fm.startDownloadingUbiquitousItem(at: real)
            }
        }
    }
}
