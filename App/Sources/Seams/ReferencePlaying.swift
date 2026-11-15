// What the song screen needs to play a streamed Apple Music track it cannot read: play, pause, seek, position.
// What a reader gets wrong: this plays through Apple's player, so no waveform, loop or envelope can exist for it.
import Foundation

@MainActor
protocol ReferencePlaying: AnyObject {
    /// The song id loaded, nil when none.
    var loadedID: String? { get }
    var isPlaying: Bool { get }
    var position: TimeInterval { get }
    /// The track's length, 0 until the player knows it.
    var duration: TimeInterval { get }
    /// Called when playback stops: nothing of the player is audible any more.
    var onIdle: (() -> Void)? { get set }
    func load(id: String, storeID: String)
    func toggle()
    func pause()
    func seek(to seconds: TimeInterval)
}

@MainActor
final class FakeReferencePlayer: ReferencePlaying {
    private(set) var loadedID: String?
    private(set) var loadedStoreID: String?
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    var duration: TimeInterval = 200
    var onIdle: (() -> Void)?

    func load(id: String, storeID: String) {
        if loadedID != id { position = 0; isPlaying = false }
        (loadedID, loadedStoreID) = (id, storeID)
    }

    func toggle() { isPlaying.toggle() }
    func pause() { if isPlaying { isPlaying = false; onIdle?() } }
    func seek(to seconds: TimeInterval) { position = seconds }
}
