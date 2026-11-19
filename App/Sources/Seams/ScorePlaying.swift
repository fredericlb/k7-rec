// The player a score's MIDI goes to; the real one sounds through the route, the fake only keeps time (docs/score.md).
import Foundation
import Observation

@MainActor
protocol ScorePlaying: AnyObject {
    var isPlaying: Bool { get }
    /// Seconds from the start of the loaded MIDI.
    var position: TimeInterval { get }
    /// Loads a score's MIDI, keeping the position and whether it played.
    func load(midi: Data) throws
    func toggle()
    func seek(to seconds: TimeInterval)
    /// Stops and forgets the loaded MIDI.
    func unload()
    /// Called when playback stops by itself or by a pause.
    var onIdle: (() -> Void)? { get set }
}

@Observable @MainActor
final class FakeScorePlayer: ScorePlaying {
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var loaded: Data?
    @ObservationIgnored var onIdle: (() -> Void)?

    func load(midi: Data) throws { loaded = midi }
    func toggle() {
        guard loaded != nil else { return }
        isPlaying.toggle()
        if !isPlaying { onIdle?() }
    }
    func seek(to seconds: TimeInterval) { position = max(0, seconds) }
    func unload() { loaded = nil; position = 0; if isPlaying { isPlaying = false; onIdle?() } }
}
