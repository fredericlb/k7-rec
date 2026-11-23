// The switch over a chord's diagram turns to the piano: the chords then read in the sounding key, without the capo.
import XCTest

final class InstrumentUITests: XCTestCase {
    func testThePianoDropsTheCapoAndTransposes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID().uuidString)/Capo Song", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "title: Capo Song\ncapo: 2\n".write(to: folder.appendingPathComponent("song.yaml"), atomically: true, encoding: .utf8)
        try "Em7   G    A7sus4\nToday is the day\n".write(to: folder.appendingPathComponent("chords.txt"), atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        app.launchArguments = ["-ImportOnLaunch", folder.path, "-OpenFirstSong", "YES", "-NoLyricsLookup", "YES", "-FreshLibrary", "YES",
                               "-instrument", "guitar"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Capo 2"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Chord Em7"].firstMatch.tap()
        let piano = app.buttons["Piano"].firstMatch
        XCTAssertTrue(piano.waitForExistence(timeout: 5), "the diagram's popover holds the switch")
        piano.tap()
        XCTAssertTrue(app.staticTexts["F#m7"].firstMatch.waitForExistence(timeout: 5), "the popover's chord moves to the sounding key")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()

        XCTAssertTrue(app.buttons["Chord B7sus4"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Capo 2"].exists)
    }
}
