// Drives the moments page by taps and writes screenshots for a look; skipped unless SHOT_DIR is set.
import AVFoundation
import XCTest

final class MomentsShot: XCTestCase {
    func testMomentsPage() throws {
        guard let dir = ProcessInfo.processInfo.environment["SIMCTL_CHILD_SHOT_DIR"] ?? ProcessInfo.processInfo.environment["SHOT_DIR"] else { throw XCTSkip("no SHOT_DIR") }
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("seed-\(UUID().uuidString).wav")
        try writeWav(wav)
        let app = XCUIApplication()
        app.launchArguments = ["-SeedTake", wav.path]
        app.launch()
        app.buttons["Takes"].tap()
        let row = app.staticTexts["Seeded take"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let detect = app.descendants(matching: .any)["detect"].firstMatch
        XCTAssertTrue(detect.waitForExistence(timeout: 5))
        shot(dir, "1-take")
        detect.tap()
        sleep(1)
        shot(dir, "2-detected")
        app.buttons["Save"].firstMatch.tap()
        app.alerts.buttons["OK"].tap()
        sleep(1)
        app.buttons["Marker"].tap()
        app.alerts.textFields.firstMatch.typeText("Chorus")
        app.alerts.buttons["OK"].tap()
        sleep(1)
        shot(dir, "3-saved")
    }

    private func shot(_ dir: String, _ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("rehearsal-ios-m4-\(name).png"))
    }

    private func writeWav(_ url: URL) throws {
        let rate = 8000.0
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
        ])
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let frames = 40 * 8000
        let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let loud: [ClosedRange<Double>] = [0...8, 14...24, 31...38]
        for i in 0..<frames {
            let t = Double(i) / rate
            let amp: Float = loud.contains { $0.contains(t) } ? 0.5 : 0.01
            buffer.floatChannelData![0][i] = amp * Float(sin(Double(i) * 0.1))
        }
        try file.write(from: buffer)
    }
}
