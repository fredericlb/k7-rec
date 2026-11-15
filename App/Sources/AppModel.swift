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
    let moments: MomentKeeping
    let appleMusic: AppleMusicSource
    let reference: ReferencePlaying
    let prefs: SongPrefs
    let metronome = MetronomeControl()
    var recording = false
    var notice: String?
    @ObservationIgnored private let deactivate: () -> Void

    init(
        library: SongLibrary? = nil,
        recorder: TakeRecording? = nil,
        player: TakePlaying? = nil,
        moments: MomentKeeping? = nil,
        appleMusic: AppleMusicSource? = nil,
        reference: ReferencePlaying? = nil,
        prefs: SongPrefs? = nil,
        deactivate: @escaping () -> Void = { AudioSessionConfig.deactivate() }
    ) {
        self.deactivate = deactivate
        self.prefs = prefs ?? SongPrefs()
        self.library = library ?? FakeSongLibrary()
        self.recorder = recorder ?? FakeTakeRecorder()
        self.player = player ?? FakeTakePlayer()
        self.moments = moments ?? FakeMomentKeeper()
        self.appleMusic = appleMusic ?? FakeAppleMusicSource()
        self.reference = reference ?? FakeReferencePlayer()
        self.player.onIdle = { [weak self] in self?.restSession() }
        self.reference.onIdle = { [weak self] in self?.restSession() }
        metronome.onStop = { [weak self] in self?.restSession() }
    }

    /// Gives the audio session back once nothing records, plays or clicks, so other apps' music resumes.
    func restSession() {
        if !recording, !player.isPlaying, !reference.isPlaying, !metronome.running { deactivate() }
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
            player: PackagePlayer(), moments: StoreMoments(store: store),
            appleMusic: LiveAppleMusicSource(authorizer: MediaAuthorizer(), store: store, songs: paths.songs),
            reference: MusicAppPlayer(), prefs: prefs)
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
        reference.pause()
        player.load(id: id, url: url)
        player.setRange(nil, loops: false)
        player.toggle()
    }

    /// Plays `span` of `id`, looped or once; a second tap on the span that plays pauses it.
    func playSpan(id: String, url: URL, span: ClosedRange<TimeInterval>, loops: Bool) {
        reference.pause()
        player.load(id: id, url: url)
        if player.isPlaying, player.range == span { player.toggle(); return }
        player.setRange(span, loops: loops)
        player.seek(to: span.lowerBound)
        if !player.isPlaying { player.toggle() }
    }

    /// Plays or pauses a streamed song through Apple's player; a file that plays gives way.
    func toggleReference(_ song: Song) {
        if player.isPlaying { player.toggle() }
        reference.load(id: song.id, storeID: song.referenceID)
        reference.toggle()
    }

    /// Asks for the library permission; false, with a notice, when it is refused.
    func allowAppleMusic() async -> Bool {
        let access = await appleMusic.requestAccess()
        if access != .authorized { notice = "Apple Music access is off. Allow it in Settings." }
        return access == .authorized
    }

    func importAppleMusic(_ items: [any MediaItemInfo]) async {
        if let message = await appleMusic.importItems(items) { notice = message }
    }

    func seek(id: String, url: URL, to seconds: TimeInterval) {
        player.load(id: id, url: url)
        player.setRange(nil, loops: false)
        player.seek(to: seconds)
    }
}
