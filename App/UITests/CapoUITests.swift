// A song whose sidecar sets a capo shows it above the chords, and Info's stepper moves it.
import XCTest

final class CapoUITests: XCTestCase {
    func testTheCapoIsShownAboveTheChordsAndSetInInfo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID().uuidString)/Capo Song", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "title: Capo Song\ncapo: 2\n".write(to: folder.appendingPathComponent("song.yaml"), atomically: true, encoding: .utf8)
        try "Am F C G\n".write(to: folder.appendingPathComponent("chords.txt"), atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        // The guitar is pinned: the instrument is a device preference another test may have left on the piano.
        app.launchArguments = ["-ImportOnLaunch", folder.path, "-OpenFirstSong", "YES", "-NoLyricsLookup", "YES", "-FreshLibrary", "YES", "-instrument", "guitar"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Capo 2"].firstMatch.waitForExistence(timeout: 15), "the chords open under their capo")
        app.buttons["Song menu"].firstMatch.tap()
        let info = app.popovers.buttons["Info"].firstMatch
        if info.waitForExistence(timeout: 3) { info.tap() } else { app.buttons["Info"].firstMatch.tap() }
        let up = app.buttons["Capo up"].firstMatch
        XCTAssertTrue(up.waitForExistence(timeout: 5))
        up.tap()
        app.buttons["Chords"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Capo 3"].firstMatch.waitForExistence(timeout: 5))
    }
}
