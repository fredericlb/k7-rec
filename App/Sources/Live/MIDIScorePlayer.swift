// A score's MIDI played by AVMIDIPlayer through the bundled SONiVOX General MIDI bank (docs/score.md).
import AVFoundation
import Observation
import RehearsalAudio

@Observable @MainActor
final class MIDIScorePlayer: ScorePlaying {
    private(set) var isPlaying = false
    @ObservationIgnored var onIdle: (() -> Void)?
    @ObservationIgnored private var player: AVMIDIPlayer?
    /// Bumped on every play and stop, so a completion from an earlier play is ignored.
    @ObservationIgnored private var generation = 0

    var position: TimeInterval { player?.currentPosition ?? 0 }

    enum Failure: LocalizedError {
        case noSoundBank
        var errorDescription: String? { "The sound bank is missing from the app." }
    }

    func load(midi: Data) throws {
        guard let bank = Bundle.main.url(forResource: "sonivox", withExtension: "sf2") else { throw Failure.noSoundBank }
        let at = position, was = isPlaying
        halt()
        let next = try AVMIDIPlayer(data: midi, soundBankURL: bank)
        next.prepareToPlay()
        next.currentPosition = min(at, next.duration)
        player = next
        if was { play() }
    }

    func toggle() { isPlaying ? pause() : play() }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        player.currentPosition = min(max(0, seconds), player.duration)
    }

    func unload() {
        let was = isPlaying
        halt()
        player = nil
        if was { onIdle?() }
    }

    private func play() {
        guard let player else { return }
        try? AudioSessionConfig.activate()
        if player.currentPosition >= player.duration - 0.05 { player.currentPosition = 0 }
        generation += 1
        let mine = generation
        isPlaying = true
        player.play { [weak self] in Task { @MainActor in self?.ended(mine) } }
    }

    private func pause() {
        halt()
        onIdle?()
    }

    /// Stops the sound but keeps the place, since AVMIDIPlayer does not promise where `stop` leaves `currentPosition`.
    private func halt() {
        guard let player else { return }
        let at = player.currentPosition
        generation += 1
        isPlaying = false
        player.stop()
        player.currentPosition = at
    }

    private func ended(_ which: Int) {
        guard which == generation, isPlaying else { return }
        isPlaying = false
        player?.currentPosition = 0
        onIdle?()
    }
}
