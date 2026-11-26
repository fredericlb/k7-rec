// A take started on a song with no timecodes scrolls its lyrics over the song's length.
import AVFoundation
import XCTest

final class TakeFollowUITests: XCTestCase {
    func testAnUntimedSongScrollsDownWhileATakeRuns() throws {
        addUIInterruptionMonitor(withDescription: "microphone") { alert in
            for label in ["Allow", "OK"] where alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            return false
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID().uuidString)/Follow Song", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Six seconds of a tone: the take reaches the last line after about six seconds.
        // The file is closed before the app reads it: AVAudioFile writes its header when it goes.
        do {
            let file = try AVAudioFile(forWriting: folder.appendingPathComponent("original.wav"), settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            ])
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 264_600)!
            buffer.frameLength = 264_600
            for i in 0..<264_600 { buffer.floatChannelData![0][i] = Float(0.3 * sin(Double(i) * 0.3)) }
            try file.write(from: buffer)
        }
        let lyrics = (1...80).map { "Line number \($0)" }.joined(separator: "\n")
        try lyrics.write(to: folder.appendingPathComponent("lyrics.txt"), atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        app.launchArguments = ["-ImportOnLaunch", folder.path, "-OpenFirstSong", "YES", "-NoLyricsLookup", "YES", "-FreshLibrary", "YES"]
        app.launch()

        // A line is a button: it can carry a time to seek to.
        let last = app.buttons["Line number 80"].firstMatch
        XCTAssertTrue(app.buttons["Line number 1"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(last.exists && last.isHittable, "the end starts out of view")
        app.buttons["Record a take"].firstMatch.tap()
        app.tap()
        guard app.buttons["Take running"].firstMatch.waitForExistence(timeout: 8) else { throw XCTSkip("the simulator could not start a take") }
        XCTAssertTrue(last.waitForExistence(timeout: 12), "the take brought the end into view")
        XCTAssertTrue(last.isHittable)
        app.buttons["Take running"].firstMatch.tap()
        app.buttons["Stop take"].firstMatch.tap()
    }
}
