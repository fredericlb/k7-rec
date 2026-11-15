// What the play buttons and the waveforms need from the player; one thing plays at a time.
import Foundation

@MainActor
protocol TakePlaying: AnyObject {
    /// The id of the loaded file, nil when none.
    var loadedID: String? { get }
    var isPlaying: Bool { get }
    /// Seconds from the start of the loaded file.
    var position: TimeInterval { get }
    /// Loads `url` under `id` unless it is already loaded; the one loaded before stops.
    func load(id: String, url: URL)
    func toggle()
    func seek(to seconds: TimeInterval)
    func unload()
    /// Called when playback stops by itself or by a pause: nothing of the player is audible any more.
    var onIdle: (() -> Void)? { get set }
}

@MainActor
final class FakeTakePlayer: TakePlaying {
    private(set) var loadedID: String?
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    var onIdle: (() -> Void)?

    func load(id: String, url: URL) {
        if loadedID != id { position = 0; isPlaying = false }
        loadedID = id
    }

    func toggle() { isPlaying.toggle(); if !isPlaying { onIdle?() } }
    func seek(to seconds: TimeInterval) { position = seconds }
    func unload() { loadedID = nil; isPlaying = false }
}
