// The reference player over MPMusicPlayerController.applicationMusicPlayer, which needs no MusicKit entitlement.
// What a reader gets wrong: the session is activated as for a take, so a take can be recorded while a track plays.
import MediaPlayer
import Observation
import RehearsalAudio

@Observable @MainActor
final class MusicAppPlayer: ReferencePlaying {
    private(set) var loadedID: String?
    private(set) var isPlaying = false
    @ObservationIgnored private let player = MPMusicPlayerController.applicationMusicPlayer
    @ObservationIgnored private var loadedStore: String?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored var onIdle: (() -> Void)?

    init() {
        player.beginGeneratingPlaybackNotifications()
        observer = NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
    }

    var position: TimeInterval { player.currentPlaybackTime.isFinite ? player.currentPlaybackTime : 0 }
    var duration: TimeInterval { player.nowPlayingItem?.playbackDuration ?? 0 }

    func load(id: String, storeID: String) {
        guard loadedStore != storeID || loadedID != id else { return }
        player.stop()
        player.setQueue(with: [storeID])
        (loadedID, loadedStore) = (id, storeID)
        sync()
    }

    func toggle() {
        if isPlaying { pause(); return }
        try? AudioSessionConfig.activate()
        player.prepareToPlay()
        player.play()
        isPlaying = true
    }

    func pause() { player.pause(); sync() }

    func seek(to seconds: TimeInterval) { player.currentPlaybackTime = seconds }

    private func sync() {
        let now = player.playbackState == .playing
        if now != isPlaying { isPlaying = now; if !now { onIdle?() } }
    }
}
