import AVFoundation
import RehearsalAudio
import XCTest

/// A song that plays keeps playing: run on the Mac (Catalyst) and the simulator, where the engine may report a configuration change at start.
@MainActor
final class PlayerStaysPlayingTests: XCTestCase {
    private func tone(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100.0, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16])
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<2 { for i in 0..<Int(frames) { buffer.floatChannelData![c][i] = 0.2 * sin(Float(i) * 0.05) } }
        try file.write(from: buffer)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAPlayingSongIsStillPlayingAfterTwoSeconds() async throws {
        let player = try TakePlayer(url: try tone(seconds: 6))
        var pauses = 0
        player.onPause = { pauses += 1 }
        try player.play()
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(player.state, .playing, "paused \(pauses) times")
        XCTAssertGreaterThan(player.positionSec, 1)
        player.stop()
    }
}
