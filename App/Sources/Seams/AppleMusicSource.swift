// What the Songs screens need from Apple Music: the permission, an import with progress, and cancelling it.
// What a reader gets wrong: a refused permission imports nothing, whatever items the caller holds.
import Foundation
import Observation
import RehearsalStore

struct AppleMusicProgress: Equatable {
    var index: Int, total: Int, fraction: Double, title: String
}

@MainActor
protocol AppleMusicSource: AnyObject {
    var access: MusicAccess { get }
    var progress: AppleMusicProgress? { get }
    func requestAccess() async -> MusicAccess
    /// Imports `items`; returns the message to show, nil when there is nothing to say.
    func importItems(_ items: [any MediaItemInfo]) async -> String?
    func cancel()
}

@Observable @MainActor
final class LiveAppleMusicSource: AppleMusicSource {
    private(set) var access: MusicAccess
    private(set) var progress: AppleMusicProgress?
    @ObservationIgnored private let authorizer: MusicAuthorizing
    @ObservationIgnored private let writer: AppleMusicWriter
    @ObservationIgnored private var task: Task<AppleMusicOutcome, Never>?

    init(authorizer: MusicAuthorizing, store: Store, songs: URL, exporter: AudioExporting = AssetExporter()) {
        self.authorizer = authorizer
        access = authorizer.access
        writer = AppleMusicWriter(store: store, songs: songs, exporter: exporter)
    }

    func requestAccess() async -> MusicAccess {
        access = await authorizer.request()
        return access
    }

    func importItems(_ items: [any MediaItemInfo]) async -> String? {
        access = authorizer.access
        guard access == .authorized else { return "Apple Music access is off. Allow it in Settings." }
        guard task == nil else { return nil }
        let (writer, total) = (writer, items.count)
        let titles = items.map(\.title)
        let report: @Sendable (AppleMusicProgress) -> Void = { [weak self] p in Task { @MainActor in self?.progress = p } }
        let t = Task.detached {
            await writer.write(items) { i, f in report(AppleMusicProgress(index: i, total: total, fraction: f, title: titles[i])) }
        }
        task = t
        let outcome = await t.value
        (task, progress) = (nil, nil)
        return outcome.message.isEmpty ? nil : outcome.message
    }

    func cancel() { task?.cancel() }
}

@MainActor
final class FakeAppleMusicSource: AppleMusicSource {
    var access: MusicAccess = .notDetermined
    var progress: AppleMusicProgress?
    private(set) var imported: [String] = []
    func requestAccess() async -> MusicAccess { access = .authorized; return access }
    func importItems(_ items: [any MediaItemInfo]) async -> String? { imported += items.map(\.itemID); return nil }
    func cancel() {}
}
