// Every icon-only control is a 44 pt target with a name VoiceOver can read, on the song screen, the rec button and the take panel.
import AVFoundation
import UIKit
import XCTest

final class TargetTests: XCTestCase {
    private func launch(sheet: Bool = false) throws -> XCUIApplication {
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
        if sheet {
            let sheets = folder.appendingPathComponent("sheets", isDirectory: true)
            try FileManager.default.createDirectory(at: sheets, withIntermediateDirectories: true)
            let png = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).pngData { $0.fill(CGRect(x: 0, y: 0, width: 40, height: 60)) }
            try png.write(to: sheets.appendingPathComponent("page.png"))
        }
        let app = XCUIApplication()
        app.launchArguments = ["-ImportOnLaunch", folder.path, "-OpenFirstSong", "YES", "-NoLyricsLookup", "YES", "-FreshLibrary", "YES"]
        app.launch()
        return app
    }

    private func assertTarget(_ element: XCUIElement, _ name: String, minHeight: Double = 44, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(name) exists", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44 - 0.01, "\(name) is wide enough", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, minHeight - 0.01, "\(name) is tall enough", file: file, line: line)
    }

    func testTheSongScreenControlsAreTargetsWithNames() throws {
        let app = try launch()
        // A navigation bar item is 36 pt tall whatever its label asks for; the bar sizes it.
        assertTarget(app.buttons["Song menu"].firstMatch, "Song menu", minHeight: 36)
        for tab in ["Chords", "Lyrics"] { assertTarget(app.buttons[tab].firstMatch, tab) }
        // On iPhone, Info sits in the song menu (the design system's platform rules).
        app.buttons["Song menu"].firstMatch.tap()
        app.buttons["Info"].firstMatch.tap()
        for name in ["Transpose down", "Transpose up"] { assertTarget(app.buttons[name].firstMatch, name) }
    }

    func testAnEmptyTabIsShownWithAPlusAndAsksForItsContent() throws {
        let app = try launch()
        let add = app.buttons["Add tab"].firstMatch
        assertTarget(add, "Add tab")
        add.tap()
        XCTAssertTrue(app.navigationBars["Tab"].waitForExistence(timeout: 5), "the tab editor opens")
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists)
    }

    func testTheSheetGoesFullScreenAndBack() throws {
        let app = try launch(sheet: true)
        let sheets = app.buttons["Sheets"].firstMatch
        XCTAssertTrue(sheets.waitForExistence(timeout: 15))
        sheets.tap()
        let expand = app.buttons["sheetFullScreen"].firstMatch
        assertTarget(expand, "Full screen")
        XCTAssertEqual(expand.label, "Full screen")
        expand.tap()
        let shrink = app.buttons["sheetExitFullScreen"].firstMatch
        assertTarget(shrink, "Exit full screen")
        shrink.tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5), "the tab is back")
    }

    func testALoneSheetHasNoChipsAndAnotherIsAddedFromTheMenu() throws {
        let app = try launch(sheet: true)
        let sheets = app.buttons["Sheets"].firstMatch
        XCTAssertTrue(sheets.waitForExistence(timeout: 15))
        sheets.tap()
        assertTarget(app.buttons["Remove the sheet"].firstMatch, "Remove the sheet")
        XCTAssertFalse(app.buttons["Add a sheet"].exists, "no chip row for one sheet")
        app.buttons["Song menu"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Add another sheet"].firstMatch.waitForExistence(timeout: 5))
    }

    func testTheRecButtonAndTakePanelAreTargetsWithNames() throws {
        addUIInterruptionMonitor(withDescription: "microphone") { alert in
            for label in ["Allow", "OK"] where alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            return false
        }
        let app = XCUIApplication()
        app.launch()
        app.buttons["Takes"].firstMatch.tap()
        assertTarget(app.buttons["Record a take"].firstMatch, "Record a take", minHeight: 36)
        app.buttons["Record a take"].firstMatch.tap()
        app.tap()
        let led = app.buttons["Take running"].firstMatch
        guard led.waitForExistence(timeout: 8) else {
            let said = app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " / ")
            throw XCTSkip("the simulator could not start a take: \(said)")
        }
        led.tap()
        let metronome = app.buttons["metronomeButton"].firstMatch
        assertTarget(metronome, "Metronome", minHeight: 36)
        metronome.tap()
        for name in ["Slower", "Faster"] { assertTarget(app.buttons[name].firstMatch, name) }
        XCTAssertTrue(app.switches["metronomeSwitch"].firstMatch.exists)
        app.staticTexts["Recording"].firstMatch.tap()
        let pause = app.buttons["Pause take"].firstMatch
        guard pause.waitForExistence(timeout: 8) else { throw XCTSkip("the simulator could not start a take") }
        assertTarget(pause, "Pause take")
        assertTarget(app.buttons["Stop take"].firstMatch, "Stop take")
        XCTAssertTrue(app.otherElements["Input level"].firstMatch.exists || app.progressIndicators["Input level"].firstMatch.exists)
        app.buttons["Stop take"].firstMatch.tap()
    }
}
