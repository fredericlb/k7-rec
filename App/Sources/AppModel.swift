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
    let scorePlayer: ScorePlaying
    let moments: MomentKeeping
    let prefs: SongPrefs
    let stems: StemMaking
    let lyrics: LyricsFetching
    let server: ServerAccount
    let metronome = MetronomeControl()
    var recording = false
    /// Whether the take panel (controls, highlights, metronome) is shown over the current screen.
    var recorderOpen = false
    /// The song whose page is open in the Songs tab.
    var shownSong: Song?
    /// Whether the Songs tab is the one in front; the other tabs keep their pages alive behind it.
    var songsInFront = true
    /// The song a take started now belongs to: the open song's, while the Songs tab is in front.
    var songForTake: Song? { songsInFront ? shownSong : nil }
    /// The level of what is heard or recorded now, linear; nil when nothing plays or records (the backdrop drifts).
    var soundLevel: Double? {
        if recording { return recorder.paused ? 0 : recorder.level }
        return player.isPlaying ? player.level : nil
    }
    /// The take just stopped, for the Takes tab to open; the tab clears it once shown.
    var stoppedTake: String?
    private(set) var lyricsBusy = false
    /// True while the instrumental is being mixed from the stems.
    private(set) var mixing = false
    /// Whether an import looks its songs up on LRCLIB; the UI tests turn it off.
    var looksUpLyrics = true
    var notice: String?
    @ObservationIgnored private let deactivate: () -> Void
    @ObservationIgnored var sync: SyncDriver?

    init(
        library: SongLibrary? = nil,
        recorder: TakeRecording? = nil,
        player: TakePlaying? = nil,
        scorePlayer: ScorePlaying? = nil,
        moments: MomentKeeping? = nil,
        prefs: SongPrefs? = nil,
        stems: StemMaking? = nil,
        lyrics: LyricsFetching? = nil,
        server: ServerAccount? = nil,
        deactivate: @escaping () -> Void = { AudioSessionConfig.deactivate() }
    ) {
        self.deactivate = deactivate
        self.prefs = prefs ?? SongPrefs()
        self.library = library ?? FakeSongLibrary()
        self.recorder = recorder ?? FakeTakeRecorder()
        self.player = player ?? FakeTakePlayer()
        self.scorePlayer = scorePlayer ?? FakeScorePlayer()
        self.moments = moments ?? FakeMomentKeeper()
        self.stems = stems ?? FakeStemMaker()
        self.lyrics = lyrics ?? FakeLyricsFetcher()
        self.server = server ?? ServerAccount()
        self.player.onIdle = { [weak self] in self?.listeningTo = nil; self?.restSession() }
        metronome.onStop = { [weak self] in self?.restSession() }
        self.scorePlayer.onIdle = { [weak self] in self?.restSession() }
    }

    /// Gives the audio session back once nothing records, plays or clicks, so other apps' music resumes.
    func restSession() {
        if !recording, !player.isPlaying, !scorePlayer.isPlaying, !metronome.running { deactivate() }
    }

    /// The real seams over the app's files; a store that cannot open falls back to memory, with a notice.
    static func live(paths: AppPaths = .live()) -> AppModel {
        paths.adoptLocalFiles(from: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
        try? paths.create()
        var failure: String?
        let store: Store
        var opened = true
        do { store = try Store(url: paths.database) } catch {
            failure = "The library could not be opened: \(error.localizedDescription)"
            store = try! Store()
            opened = false
        }
        let prefs = SongPrefs()
        let model = AppModel(
            library: StoreSongLibrary(store: store, songsFolder: paths.songs),
            recorder: StoreTakeRecorder(store: store, takesFolder: paths.takes, headsetInput: { prefs.headsetInput }),
            player: PackagePlayer(), scorePlayer: MIDIScorePlayer(), moments: StoreMoments(store: store),
            prefs: prefs, stems: LiveStemMaker(songs: paths.songs, models: paths.models), lyrics: LRCLibClient(), server: ServerAccount(files: ServerFiles(), secrets: KeychainStore()))
        model.notice = failure
        model.looksUpLyrics = !DebugLaunch.noLyricsLookup
        // A library that fell back to memory is never mirrored: its emptiness would read as deletions.
        if opened {
            let driver = SyncDriver(store: store, paths: paths)
            model.sync = driver
            (model.recorder as? StoreTakeRecorder)?.onDeleted = { driver.deleted(takeID: $0) }
        }
        return model
    }

    func startTake(song: Song? = nil) async {
        guard !recording else { return }
        let title = song?.title ?? "Take " + Date().formatted(date: .abbreviated, time: .shortened)
        recording = await recorder.start(songID: song?.id ?? "", title: title)
        if !recording { notice = "The recording could not start: " + (recorder.failure ?? "the microphone did not answer.") }
    }

    /// Ends the take and, once it is saved, closes the panel and opens the take's page.
    func stopTake() async {
        stopListening()
        let saved = await recorder.stop()
        recording = false
        notice = recorder.failure ?? notice
        restSession()
        if let saved {
            recorderOpen = false
            stoppedTake = saved
        }
    }

    func resumeTake() async {
        stopListening()
        await recorder.resume()
        notice = recorder.failure ?? notice
        if !recorder.isRecording { recording = false; restSession() }
    }

    /// The player's id for what the running take recorded; it grows, so it is loaded afresh each time.
    private static let liveID = "live-take"

    /// The highlight now heard, nil when none.
    private(set) var listeningTo: Int?

    /// Hears a highlight of the running take in a loop: the take rests first, so the speaker is never recorded; a second tap stops it.
    func listen(to highlight: Highlight) {
        if listeningTo == highlight.id, player.isPlaying { player.toggle(); return }
        guard let heard = recorder.listen(to: highlight) else { notice = "That highlight cannot be played yet."; return }
        player.unload()
        player.load(id: Self.liveID, url: heard.url)
        player.setGain(heard.gain)
        player.setRange(heard.span, loops: true)
        player.seek(to: heard.span.lowerBound)
        listeningTo = highlight.id
        if !player.isPlaying { player.toggle() }
    }

    private func stopListening() {
        guard listeningTo != nil else { return }
        player.unload()
        listeningTo = nil
    }

    /// At launch: raw takes a crash left become saved takes.
    func recoverTakes() async {
        let n = await recorder.recoverLeftovers()
        if n > 0 { notice = n == 1 ? "A take from the last session was recovered." : "\(n) takes from the last session were recovered." }
        if recorder.unrecovered > 0 { notice = "\(recorder.unrecovered) unfinished takes could not be recovered; they stay in the Takes folder." }
    }

    func importURLs(_ urls: [URL]) async {
        await library.refresh()
        let known = Set(library.songs.map(\.id))
        if let failure = await library.importURLs(urls) { notice = failure }
        await fetchLyricsForNewSongs(besides: known)
    }

    /// Downloads the picked files of the user's server and imports them as any picked audio; false when a download failed.
    func importFromServer(_ paths: [String]) async -> Bool {
        do {
            let got = try await server.fetch(paths)
            defer { try? FileManager.default.removeItem(at: got.folder) }
            await importURLs(got.urls)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    /// Writes a song the user misses into MISSING-SONGS.md on the file server, and says what came of it.
    func reportMissingSong(artist: String, title: String) async {
        let (a, t) = (artist.trimmingCharacters(in: .whitespacesAndNewlines), title.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !a.isEmpty, !t.isEmpty else { notice = "Enter an artist and a title."; return }
        do {
            try await server.addMissingSong(artist: a, title: t)
            notice = "\(ServerAccount.tidy(a)) - \(ServerAccount.tidy(t)) was added to MISSING-SONGS.md."
        } catch { notice = error.localizedDescription }
    }

    /// Looks up the lyrics of the user's song on LRCLIB, from the song menu; says what came of it.
    func downloadLyrics(for song: Song) async {
        guard !lyricsBusy else { return }
        lyricsBusy = true
        defer { lyricsBusy = false }
        notice = await fetchLyrics(for: song) ?? "Lyrics downloaded for \(song.title)."
    }

    /// After an import: each song that arrived without lyrics is looked up; failures are told once, with the way to retry.
    private func fetchLyricsForNewSongs(besides known: Set<String>) async {
        guard looksUpLyrics else { return }
        await library.refresh()
        let fresh = library.songs.filter { !known.contains($0.id) && !$0.hasLyrics }
        var failed: [String] = []
        for song in fresh where await fetchLyrics(for: song) != nil { failed.append(song.title) }
        guard !failed.isEmpty else { return }
        let why = failed.count == 1 ? "No lyrics were downloaded for \(failed[0])." : "No lyrics were downloaded for \(failed.count) songs."
        notice = [notice, why + " Try again from the song's menu."].compactMap { $0 }.joined(separator: "\n")
    }

    /// Nil when the lyrics were saved, else why not. A song with lyrics only gets timing; its words are never replaced.
    private func fetchLyrics(for song: Song) async -> String? {
        let current = library.songs.first { $0.id == song.id } ?? song
        let found: FoundLyrics?
        do { found = try await lyrics.find(title: current.title, artist: current.artist, audio: current.audioURL) } catch {
            return "LRCLIB could not be reached."
        }
        guard let found else { return "LRCLIB has no lyrics for \(current.title)." }
        if current.hasLyrics {
            guard let synced = found.synced, case .success(let r) = SongText.timedLyrics(current.lyrics, lrc: synced) else {
                return "LRCLIB has no timing that fits the lyrics of \(current.title)."
            }
            return await library.saveLyrics(r.text, for: current)
        }
        var text = found.plain
        if let synced = found.synced, case .success(let r) = SongText.timedLyrics(found.plain, lrc: synced) { text = r.text }
        return await library.saveLyrics(text, for: current)
    }

    /// Whether the song plays its instrumental: the reader chose it and the file is there.
    func playsInstrumental(_ song: Song) -> Bool { prefs.isInstrumental(song.id) && stems.instrumentalURL(for: song) != nil }

    /// The id the player knows the song's sound by; each version has its own, so the two never share a loaded file.
    func playID(of song: Song) -> String { "song:" + song.id + (playsInstrumental(song) ? ":instrumental" : "") }

    /// The file the play button plays: the instrumental or the song's own audio.
    func playURL(of song: Song) -> URL? { playsInstrumental(song) ? stems.instrumentalURL(for: song) : song.audioURL }

    /// Switches between the full song and its instrumental, mixing the instrumental once; the playing position carries over.
    func switchVersion(of song: Song) async {
        guard !mixing else { return }
        let was = playID(of: song)
        let (loaded, position, playing) = (player.loadedID == was, player.position, player.isPlaying)
        if playsInstrumental(song) { prefs.setInstrumental(false, for: song.id) } else {
            if stems.instrumentalURL(for: song) == nil {
                mixing = true
                let failure = await stems.makeInstrumental(for: song)
                mixing = false
                if let failure { notice = failure; return }
            }
            prefs.setInstrumental(true, for: song.id)
        }
        guard loaded, let url = playURL(of: song) else { return }
        player.load(id: playID(of: song), url: url)
        player.setRange(nil, loops: false)
        player.seek(to: position)
        if playing { player.toggle() }
    }

    /// Plays or pauses `id`, loading `url` first when another file is loaded.
    func togglePlay(id: String, url: URL) {
        player.load(id: id, url: url)
        player.setRange(nil, loops: false)
        player.toggle()
    }

    /// Plays `span` of `id`, looped or once; a second tap on the span that plays pauses it.
    func playSpan(id: String, url: URL, span: ClosedRange<TimeInterval>, loops: Bool) {
        player.load(id: id, url: url)
        if player.isPlaying, player.range == span { player.toggle(); return }
        player.setRange(span, loops: loops)
        player.seek(to: span.lowerBound)
        if !player.isPlaying { player.toggle() }
    }

    func seek(id: String, url: URL, to seconds: TimeInterval) {
        player.load(id: id, url: url)
        player.setRange(nil, loops: false)
        player.seek(to: seconds)
    }
}
