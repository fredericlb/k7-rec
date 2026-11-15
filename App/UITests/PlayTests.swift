// A real tap on the header's play button starts playback and the button turns into Pause.
import AVFoundation
import XCTest

final class PlayTests: XCTestCase {
    func testHeaderPlayStartsPlayback() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID().uuidString)/Probe Song", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeWav(folder.appendingPathComponent("original.wav"))
        try "Am F\n".write(to: folder.appendingPathComponent("chords.txt"), atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        app.launchArguments = ["-ImportOnLaunch", folder.path, "-OpenFirstSong", "YES"]
        app.launch()
        let play = app.buttons["Play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(play.frame.width, 44, "a thumb must be able to hit it")
        play.tap()
        sleep(2)
        XCTAssertTrue(app.buttons["Pause"].firstMatch.exists)
    }

    private func writeWav(_ url: URL) throws {
        let rate = 8000.0
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
        ])
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 80_000)!
        buffer.frameLength = 80_000
        for i in 0..<80_000 { buffer.floatChannelData![0][i] = 0.4 * Float(sin(Double(i) * 0.1)) }
        try file.write(from: buffer)
    }
}
