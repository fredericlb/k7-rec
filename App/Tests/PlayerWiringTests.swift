// The player seam follows the package's player when something else pauses it, and the session rests when idle.
import RehearsalAudio
import XCTest
@testable import Rehearsal

@MainActor
final class PlayerWiringTests: XCTestCase {
    func testASeamPlayerPausedByAnotherPlayerNoLongerSaysItPlays() async throws {
        let wav = try tempFolder().appendingPathComponent("a.wav")
        try makeWav(at: wav, seconds: 2, amp: 0.5)
        let player = PackagePlayer()
        player.load(id: "song", url: wav)
        player.toggle()
        XCTAssertTrue(player.isPlaying)

        let other = try TakePlayer(url: wav)
        try other.play()
        defer { other.stop() }

        XCTAssertFalse(player.isPlaying, "the floor went to another player")
    }

    func testTheSessionIsGivenBackWhenPlaybackStopsAndOnlyThen() async throws {
        let wav = try tempFolder().appendingPathComponent("a.wav")
        try makeWav(at: wav, seconds: 2, amp: 0.5)
        var rested = 0
        let model = AppModel(player: PackagePlayer(), deactivate: { rested += 1 })

        model.togglePlay(id: "a", url: wav)
        XCTAssertEqual(rested, 0, "playing keeps the session")
        model.togglePlay(id: "a", url: wav)
        XCTAssertEqual(rested, 1, "a pause with nothing else running gives it back")
    }
}
