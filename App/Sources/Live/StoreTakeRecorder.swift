// Records takes through TakeRecorder and keeps them as Take rows; the Takes list observes the store.
// What a reader gets wrong: a listing skips the envelope field, so `take(id:)` is what loads it.
import Foundation
import Observation
import RehearsalAudio
import RehearsalStore

@Observable @MainActor
final class StoreTakeRecorder: TakeRecording {
    private(set) var level = 0.0
    private(set) var paused = false
    private(set) var takes: [Take] = []
    private(set) var failure: String?
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let makeInput: @Sendable () -> AudioInput
    @ObservationIgnored private let askMicrophone: @Sendable () async -> Bool
    @ObservationIgnored private var recorder: TakeRecorder?
    @ObservationIgnored private var pending: (songID: String, title: String, date: Date)?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(
        store: Store, takesFolder: URL,
        makeInput: @escaping @Sendable () -> AudioInput = { EngineInput() },
        askMicrophone: @escaping @Sendable () async -> Bool = { await AudioSessionConfig.requestMicrophone() }
    ) {
        (self.store, folder, self.makeInput, self.askMicrophone) = (store, takesFolder, makeInput, askMicrophone)
        let listing = Query<RehearsalStore.Take>(
            fields: ["songId", "title", "createdAt", "duration", "gain", "audioPath"], orderBy: "createdAt", descending: true)
        tasks.append(Task { [weak self] in
            do { for try await v in store.observe(listing) { self?.takes = v.map { self?.map($0) ?? Take(id: $0.id, title: "", date: .now, duration: 0) } } } catch {}
        })
    }

    deinit { tasks.forEach { $0.cancel() } }

    var elapsed: TimeInterval { recorder?.elapsedSec ?? 0 }

    func start(songID: String, title: String) async -> Bool {
        guard recorder == nil, await askMicrophone() else { failure = "The microphone is not allowed."; return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let r = TakeRecorder(input: makeInput(), directory: folder)
            try r.start()
            recorder = r
            pending = (songID, title, .now)
            (paused, level, failure) = (false, 0, nil)
            tasks.append(Task { [weak self] in
                for await e in r.events {
                    if case .level(let rms, _) = e { self?.level = min(1, Double(rms) * 3) } else if case .lost = e { self?.paused = true }
                }
            })
            return true
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    func pause() { recorder?.pause(); paused = true }

    func resume() {
        guard (try? recorder?.resume()) != nil else { return }
        paused = false
    }

    func stop() async {
        guard let r = recorder, let info = pending else { return }
        recorder = nil
        pending = nil
        level = 0
        do {
            let result = try await r.stop()
            let row = RehearsalStore.Take(
                songId: info.songID, title: info.title, createdAt: info.date.timeIntervalSince1970, duration: result.durationSec,
                envelope: result.envelope.samples.map { Float($0) }, gain: 1, audioPath: result.url.lastPathComponent)
            try await store.put(row)
        } catch RecorderError.nothingRecorded {
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    func take(id: String) async -> Take? {
        (try? await store.get(RehearsalStore.Take.self, id)).map { map($0) }
    }

    func rename(id: String, title: String) async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = try? await store.write { tx in if var t = try tx.get(RehearsalStore.Take.self, id) { t.title = name; try tx.put(t) } }
    }

    func delete(id: String) async {
        guard let row = try? await store.get(RehearsalStore.Take.self, id) else { return }
        try? await store.delete(RehearsalStore.Take.self, id)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(row.audioPath))
    }

    private func map(_ t: RehearsalStore.Take) -> Take {
        Take(id: t.id, songID: t.songId, title: t.title, date: Date(timeIntervalSince1970: t.createdAt), duration: t.duration,
             envelope: t.envelope.map(Double.init), gain: t.gain,
             audioURL: t.audioPath.isEmpty ? nil : folder.appendingPathComponent(t.audioPath))
    }
}
