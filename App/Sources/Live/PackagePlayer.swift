// The player seam over TakePlayer: one file loaded at a time, the position pulled by whoever draws.
import Foundation
import Observation
import RehearsalAudio

@Observable @MainActor
final class PackagePlayer: TakePlaying {
    private(set) var loadedID: String?
    private(set) var isPlaying = false
    private(set) var range: ClosedRange<TimeInterval>?
    @ObservationIgnored private var player: TakePlayer?
    @ObservationIgnored var onIdle: (() -> Void)?

    var position: TimeInterval { player?.positionSec ?? 0 }

    func load(id: String, url: URL) {
        guard loadedID != id else { return }
        unload()
        guard let p = try? TakePlayer(url: url) else { return }
        p.onFinish = { [weak self] in self?.isPlaying = false; self?.onIdle?() }
        p.onPause = { [weak self] in self?.isPlaying = false; self?.onIdle?() }
        player = p
        loadedID = id
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause(); isPlaying = false } else { isPlaying = (try? player.play()) != nil }
    }

    func setRange(_ range: ClosedRange<TimeInterval>?, loops: Bool) {
        guard range != nil || self.range != nil else { return }
        player?.setRange(range, loops: loops)
        self.range = range
    }

    func seek(to seconds: TimeInterval) { player?.seek(to: seconds) }

    func unload() {
        player?.stop()
        if isPlaying { onIdle?() }
        (player, loadedID, isPlaying, range) = (nil, nil, false, nil)
    }
}
