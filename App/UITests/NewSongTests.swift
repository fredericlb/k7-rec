// A song made from Add song opens at once, with nothing to play and no LRCLIB, stems or timing in its menu.
import XCTest

final class NewSongUITests: XCTestCase {
    func testANewSongOpensWithoutPlayOrAudioActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-NoLyricsLookup", "YES", "-FreshLibrary", "YES"]
        app.launch()
        let add = app.buttons["Add song"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let new = app.buttons["New song"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        let title = app.alerts.textFields["Title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Sketch")
        app.alerts.buttons["Create"].firstMatch.tap()

        let menu = app.buttons["Song menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the new song opens")
        XCTAssertTrue(app.staticTexts["Sketch"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Play"].exists)
        menu.tap()
        XCTAssertTrue(app.popovers.firstMatch.waitForExistence(timeout: 5))
        for gone in ["Separate into stems", "Download lyrics from LRCLIB", "Import timing from an LRC file"] {
            XCTAssertFalse(app.popovers.buttons[gone].exists, gone)
        }
    }
}
