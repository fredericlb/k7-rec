// The stems sheet's player: the four stems and their mix, observable, one session per open sheet.
import Foundation
import Observation
import RehearsalStems

@Observable @MainActor
final class StemSession {
    private(set) var isPlaying = false
    var mix = StemMix() { didSet { player.mix = mix } }
    @ObservationIgnored private let player: StemPlayer
    @ObservationIgnored var onIdle: (() -> Void)?

    var duration: Double { player.durationSec }
    var position: Double { player.positionSec }

    init(urls: [Stem: URL]) throws {
        player = try StemPlayer(urls: urls)
        player.onPause = { [weak self] in self?.isPlaying = false; self?.onIdle?() }
        player.onFinish = { [weak self] in self?.isPlaying = false; self?.onIdle?() }
    }

    func toggle() {
        if isPlaying { player.pause() } else { isPlaying = (try? player.play()) != nil }
    }

    func seek(to seconds: Double) { player.seek(to: seconds) }

    func stop() {
        let was = isPlaying
        player.stop()
        isPlaying = false
        if was { onIdle?() }
    }
}
