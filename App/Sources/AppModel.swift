// The app's state holder; it only talks to the seams, `live()` is the one place that builds the real ones.
import Observation
import RehearsalAudio
import RehearsalStore
import SwiftUI

@Observable @MainActor
final class AppModel {
    let library: SongLibrary
    let recorder: TakeRecording
    let player: TakePlaying
    let prefs: SongPrefs
    let metronome = MetronomeControl()
    var recording = false
    var notice: String?
    @ObservationIgnored private let deactivate: () -> Void

    init(
        library: SongLibrary? = nil,
        recorder: TakeRecording? = nil,
        player: TakePlaying? = nil,
        prefs: SongPrefs? = nil,
        deactivate: @escaping () -> Void = { AudioSessionConfig.deactivate() }
    ) {
        self.deactivate = deactivate
        self.prefs = prefs ?? SongPrefs()
        self.library = library ?? FakeSongLibrary()
        self.recorder = recorder ?? FakeTakeRecorder()
        self.player = player ?? FakeTakePlayer()
        self.player.onIdle = { [weak self] in self?.restSession() }
        metronome.onStop = { [weak self] in self?.restSession() }
    }

    /// Gives the audio session back once nothing records, plays or clicks, so other apps' music resumes.
    func restSession() {
        if !recording, !player.isPlaying, !metronome.running { deactivate() }
    }

    /// The real seams over the app's files; a store that cannot open falls back to memory, with a notice.
    static func live(paths: AppPaths = .live()) -> AppModel {
        try? paths.create()
        var failure: String?
        let store: Store
        do { store = try Store(url: paths.database) } catch {
            failure = "The library could not be opened: \(error.localizedDescription)"
            store = try! Store()
        }
        let prefs = SongPrefs()
        let model = AppModel(
            library: StoreSongLibrary(store: store, songsFolder: paths.songs),
            recorder: StoreTakeRecorder(store: store, takesFolder: paths.takes, headsetInput: { prefs.headsetInput }),
            player: PackagePlayer(), prefs: prefs)
        model.notice = failure
        return model
    }

    func startTake(song: Song? = nil) async {
        guard !recording else { return }
        let title = song?.title ?? "Take " + Date().formatted(date: .abbreviated, time: .shortened)
        recording = await recorder.start(songID: song?.id ?? "", title: title)
        if !recording { notice = "The recording could not start. Check the microphone in Settings." }
    }

    func stopTake() async {
        await recorder.stop()
        recording = false
        notice = recorder.failure ?? notice
        restSession()
    }

    func resumeTake() async {
        await recorder.resume()
        notice = recorder.failure ?? notice
    }

    /// At launch: raw takes a crash left become saved takes.
    func recoverTakes() async {
        let n = await recorder.recoverLeftovers()
        if n > 0 { notice = n == 1 ? "A take from the last session was recovered." : "\(n) takes from the last session were recovered." }
    }

    func importURLs(_ urls: [URL]) async {
        if let failure = await library.importURLs(urls) { notice = failure }
    }

    /// Plays or pauses `id`, loading `url` first when another file is loaded.
    func togglePlay(id: String, url: URL) {
        player.load(id: id, url: url)
        player.toggle()
    }

    func seek(id: String, url: URL, to seconds: TimeInterval) {
        player.load(id: id, url: url)
        player.seek(to: seconds)
    }
}
