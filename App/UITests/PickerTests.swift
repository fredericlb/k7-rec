// Each of the song menu's file pickers opens when its button is tapped, one after the other on the same screen.
import AVFoundation
import XCTest

final class PickerTests: XCTestCase {
    private func launch() throws -> XCUIApplication {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID().uuidString)/Pick Song", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = try AVAudioFile(forWriting: folder.appendingPathComponent("original.wav"), settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 8000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
        ])
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8000)!
        buffer.frameLength = 8000
        try file.write(from: buffer)
        try "la la\n".write(to: folder.appendingPathComponent("lyrics.txt"), atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        app.launchArguments = ["-ImportOnLaunch", folder.path, "-OpenFirstSong", "YES", "-NoLyricsLookup", "YES", "-FreshLibrary", "YES"]
        app.launch()
        return app
    }

    private func opens(_ app: XCUIApplication, _ button: String) -> Bool {
        app.buttons["Song menu"].firstMatch.tap()
        let item = app.buttons[button].firstMatch
        guard item.waitForExistence(timeout: 5) else { return false }
        item.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        let shown = cancel.waitForExistence(timeout: 5)
        if shown { cancel.tap(); _ = app.buttons["Song menu"].firstMatch.waitForExistence(timeout: 5) }
        return shown
    }

    func testBothPickersOpen() throws {
        let app = try launch()
        XCTAssertTrue(app.buttons["Song menu"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(opens(app, "Add a sheet"), "the sheet picker opens")
        XCTAssertTrue(opens(app, "Import timing from an LRC file"), "the LRC picker opens")
        XCTAssertTrue(opens(app, "Add a sheet"), "the sheet picker opens again")
    }
}
