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
    private(set) var pauseCause: PauseCause?
    private(set) var takes: [Take] = []
    private(set) var failure: String?
    @ObservationIgnored let store: Store
    @ObservationIgnored let folder: URL
    @ObservationIgnored private let makeInput: @Sendable () -> AudioInput
    @ObservationIgnored private let makeSession: @Sendable () -> SessionHost
    @ObservationIgnored private let askMicrophone: @Sendable () async -> Bool
    @ObservationIgnored private let headsetInput: @MainActor () -> Bool
    @ObservationIgnored private var recorder: TakeRecorder?
    @ObservationIgnored private var pending: (songID: String, title: String, date: Date)?
    @ObservationIgnored private var parts: [TakeResult] = []
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(
        store: Store, takesFolder: URL,
        makeInput: @escaping @Sendable () -> AudioInput = { EngineInput() },
        makeSession: @escaping @Sendable () -> SessionHost = { SystemSession() },
        askMicrophone: @escaping @Sendable () async -> Bool = { await AudioSessionConfig.requestMicrophone() },
        headsetInput: @escaping @MainActor () -> Bool = { false }
    ) {
        (self.store, folder, self.makeInput, self.makeSession) = (store, takesFolder, makeInput, makeSession)
        (self.askMicrophone, self.headsetInput) = (askMicrophone, headsetInput)
        let listing = Query<RehearsalStore.Take>(
            fields: ["songId", "title", "createdAt", "duration", "gain", "audioPath"], orderBy: "createdAt", descending: true)
        tasks.append(Task { [weak self] in
            do { for try await v in store.observe(listing) { self?.takes = v.map { self?.map($0) ?? Take(id: $0.id, title: "", date: .now, duration: 0) } } } catch {}
        })
    }

    deinit { tasks.forEach { $0.cancel() }; watcher?.cancel() }

    var isRecording: Bool { recorder != nil }

    var elapsed: TimeInterval { (recorder?.elapsedSec ?? 0) + (parts.last?.durationSec ?? 0) }

    func start(songID: String, title: String) async -> Bool {
        guard recorder == nil, await askMicrophone() else { failure = "The microphone is not allowed."; return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try open(extending: nil)
            pending = (songID, title, .now)
            (paused, pauseCause, level, failure, parts) = (false, nil, 0, nil, [])
            return true
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    func pause() {
        recorder?.pause()
        (paused, pauseCause) = (true, .user)
    }

    /// A rate change while paused ends the part and continues it, as docs/audio.md says.
    func resume() async {
        guard let r = recorder else { return }
        do {
            try r.resume()
            (paused, pauseCause) = (false, nil)
        } catch RecorderError.rateChanged {
            await continueOnNewRate(r)
        } catch {
            failure = error.localizedDescription
        }
    }

    func stop() async {
        guard let r = recorder, let info = pending else { return }
        (recorder, pending, level, paused, pauseCause) = (nil, nil, 0, false, nil)
        watcher?.cancel()
        do {
            try await save(try await r.stop(), info)
        } catch RecorderError.nothingRecorded {
            if let last = parts.last { await saveQuietly(last, info) }
        } catch {
            failure = error.localizedDescription
        }
        parts = []
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

    private func open(extending: ExistingTake?) throws {
        let r = TakeRecorder(input: makeInput(), directory: folder, session: makeSession(), headsetInput: headsetInput())
        try r.start(extending: extending)
        recorder = r
        watcher?.cancel()
        watcher = Task { [weak self] in
            for await e in r.events {
                if case .level(let rms, _) = e { self?.level = min(1, Double(rms) * 3) } else if case .lost = e { self?.lost(r) }
            }
        }
    }

    private func lost(_ r: TakeRecorder) {
        paused = true
        pauseCause = switch r.pauseReason { case .interrupted: .interrupted; case .inputLost: .inputLost; default: .user }
    }

    private func continueOnNewRate(_ r: TakeRecorder) async {
        guard let info = pending else { return }
        do {
            let part = try await r.stop()
            parts.append(part)
            try open(extending: ExistingTake(url: part.url, envelope: part.envelope))
            (paused, pauseCause) = (false, nil)
        } catch RecorderError.nothingRecorded {
            do { try open(extending: parts.last.map { ExistingTake(url: $0.url, envelope: $0.envelope) }); (paused, pauseCause) = (false, nil) } catch { failure = error.localizedDescription }
        } catch {
            failure = error.localizedDescription
            if let last = parts.last { (recorder, pending) = (nil, nil); await saveQuietly(last, info) }
        }
    }

    private func saveQuietly(_ result: TakeResult, _ info: (songID: String, title: String, date: Date)) async {
        do { try await save(result, info) } catch { failure = error.localizedDescription }
    }

    /// Files the row, then frees the raw inputs and the m4a parts the final file already holds.
    private func save(_ result: TakeResult, _ info: (songID: String, title: String, date: Date)) async throws {
        try await store.put(row(of: result, songID: info.songID, title: info.title, date: info.date))
        result.confirmSaved()
        for part in parts where part.url != result.url {
            part.confirmSaved()
            try? FileManager.default.removeItem(at: part.url)
        }
    }

    func row(of result: TakeResult, songID: String, title: String, date: Date) -> RehearsalStore.Take {
        RehearsalStore.Take(
            songId: songID, title: title, createdAt: date.timeIntervalSince1970, duration: result.durationSec,
            envelope: result.envelope.samples.map { Float($0) }, gain: 1, audioPath: result.url.lastPathComponent)
    }

    private func map(_ t: RehearsalStore.Take) -> Take {
        Take(id: t.id, songID: t.songId, title: t.title, date: Date(timeIntervalSince1970: t.createdAt), duration: t.duration,
             envelope: t.envelope.map(Double.init), gain: t.gain,
             audioURL: t.audioPath.isEmpty ? nil : folder.appendingPathComponent(t.audioPath))
    }
}
