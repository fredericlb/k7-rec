// Every icon-only control is a 44 pt target with a name VoiceOver can read, on the song screen and in the recorder bar.
import AVFoundation
import XCTest

final class TargetTests: XCTestCase {
    private func launch() throws -> XCUIApplication {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID().uuidString)/Target Song", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = try AVAudioFile(forWriting: folder.appendingPathComponent("original.wav"), settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 8000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
        ])
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8000)!
        buffer.frameLength = 8000
        try file.write(from: buffer)
        try "Am F\n".write(to: folder.appendingPathComponent("chords.txt"), atomically: true, encoding: .utf8)
        try "la la\n".write(to: folder.appendingPathComponent("lyrics.txt"), atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        app.launchArguments = ["-ImportOnLaunch", folder.path, "-OpenFirstSong", "YES"]
        app.launch()
        return app
    }

    private func assertTarget(_ element: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(name) exists", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, "\(name) is wide enough", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, "\(name) is tall enough", file: file, line: line)
    }

    func testTheSongScreenControlsAreTargetsWithNames() throws {
        let app = try launch()
        assertTarget(app.buttons["Song menu"].firstMatch, "Song menu")
        for tab in ["Chords", "Lyrics", "Info"] { assertTarget(app.buttons[tab].firstMatch, tab) }
        app.buttons["Song menu"].firstMatch.tap()
        for name in ["Slower", "Faster", "Transpose down", "Transpose up", "Start metronome"] { assertTarget(app.buttons[name].firstMatch, name) }
    }

    func testTheRecorderBarButtonsAreTargetsWithNames() throws {
        addUIInterruptionMonitor(withDescription: "microphone") { alert in
            for label in ["Allow", "OK"] where alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            return false
        }
        let app = XCUIApplication()
        app.launch()
        app.buttons["Takes"].tap()
        app.buttons["Record a take"].tap()
        app.tap()
        let pause = app.buttons["Pause take"].firstMatch
        guard pause.waitForExistence(timeout: 8) else { throw XCTSkip("the simulator could not start a take") }
        assertTarget(pause, "Pause take")
        assertTarget(app.buttons["Stop take"].firstMatch, "Stop take")
        XCTAssertTrue(app.otherElements["Input level"].firstMatch.exists || app.progressIndicators["Input level"].firstMatch.exists)
        app.buttons["Stop take"].firstMatch.tap()
    }
}
