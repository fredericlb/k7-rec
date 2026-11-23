// The star in a song's bar makes it a favourite, and the Songs list then shows it first.
import XCTest

final class FavoriteUITests: XCTestCase {
    private func create(_ app: XCUIApplication, _ title: String) {
        app.buttons["Add song"].firstMatch.tap()
        app.buttons["New song"].firstMatch.tap()
        let field = app.alerts.textFields["Title"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(title)
        app.alerts.buttons["Create"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Song menu"].firstMatch.waitForExistence(timeout: 10))
    }

    func testAStarredSongIsListedFirst() {
        let app = XCUIApplication()
        app.launchArguments = ["-NoLyricsLookup", "YES", "-FreshLibrary", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Add song"].firstMatch.waitForExistence(timeout: 15))
        create(app, "Older")
        app.buttons["Add to favourites"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Remove from favourites"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        create(app, "Newer")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let older = app.buttons.containing(.staticText, identifier: "Older").firstMatch
        let newer = app.buttons.containing(.staticText, identifier: "Newer").firstMatch
        XCTAssertTrue(newer.waitForExistence(timeout: 5))
        XCTAssertLessThan(older.frame.minY, newer.frame.minY, "the favourite is above the newer song")
    }
}
