// The metronome the song menu drives; the app owns it, so the click outlives the popover that started it.
import Observation
import RehearsalAudio

@Observable @MainActor
final class MetronomeControl {
    static let range = 30.0...300.0
    var bpm = 120.0
    private(set) var running = false
    @ObservationIgnored private let metronome: Metronome

    init(metronome: Metronome? = nil) {
        let click = metronome ?? Metronome()
        self.metronome = click
        click.onHalt = { [weak self] in self?.running = false; self?.onStop?() }
    }

    func step(_ delta: Double) {
        bpm = min(max(bpm + delta, Self.range.lowerBound), Self.range.upperBound)
        if running { start() }
    }

    func toggle() { running ? stop() : start() }

    @ObservationIgnored var onStop: (() -> Void)?

    func stop() {
        metronome.stop()
        running = false
        onStop?()
    }

    private func start() { running = (try? metronome.start(bpm: bpm, startSec: 0)) != nil }
}
