// What the play buttons and the waveforms need from the player; one thing plays at a time.
import Foundation

@MainActor
protocol TakePlaying: AnyObject {
    /// The id of the loaded file, nil when none.
    var loadedID: String? { get }
    var isPlaying: Bool { get }
    /// Seconds from the start of the loaded file.
    var position: TimeInterval { get }
    /// What is heard now, linear like the recorder's level (RMS × 3, at most 1); 0 unless playing.
    var level: Double { get }
    /// Loads `url` under `id` unless it is already loaded; the one loaded before stops.
    func load(id: String, url: URL)
    func toggle()
    /// The loaded file's playback gain, 1 for a levelled take.
    func setGain(_ gain: Double)
    func seek(to seconds: TimeInterval)
    func unload()
    /// Called when playback stops by itself or by a pause: nothing of the player is audible any more.
    var onIdle: (() -> Void)? { get set }
    /// The span being played, nil for the whole file.
    var range: ClosedRange<TimeInterval>? { get }
    /// Plays only `range`, looped or once; nil restores the whole file.
    func setRange(_ range: ClosedRange<TimeInterval>?, loops: Bool)
}

@MainActor
final class FakeTakePlayer: TakePlaying {
    private(set) var loadedID: String?
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    var level = 0.0
    var onIdle: (() -> Void)?
    private(set) var range: ClosedRange<TimeInterval>?

    func setRange(_ range: ClosedRange<TimeInterval>?, loops: Bool) { self.range = range }

    func load(id: String, url: URL) {
        if loadedID != id { position = 0; isPlaying = false }
        loadedID = id
    }

    func setGain(_ gain: Double) {}
    func toggle() { isPlaying.toggle(); if !isPlaying { onIdle?() } }
    func seek(to seconds: TimeInterval) { position = seconds }
    func unload() { loadedID = nil; isPlaying = false }
}
