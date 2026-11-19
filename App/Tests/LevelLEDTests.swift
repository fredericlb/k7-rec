// The rec button's LED colour: black at silence, green then orange in the middle, red at the top.
import XCTest
@testable import Rehearsal

final class LevelLEDTests: XCTestCase {
    func testTheLEDGoesBlackGreenOrangeRedAndClamps() {
        XCTAssertEqual(LevelLED.rgb(0).red + LevelLED.rgb(0).green + LevelLED.rgb(0).blue, 0)
        let green = LevelLED.rgb(0.35)
        XCTAssertGreaterThan(green.green, green.red)
        let orange = LevelLED.rgb(0.7)
        XCTAssertEqual(orange.red, 1)
        XCTAssertEqual(orange.green, 0.6, accuracy: 0.001)
        XCTAssertEqual(LevelLED.rgb(1).red, 1)
        XCTAssertLessThan(LevelLED.rgb(1).green, 0.2)
        XCTAssertEqual(LevelLED.rgb(5).green, LevelLED.rgb(1).green)
        XCTAssertEqual(LevelLED.rgb(-1).red, 0)
        XCTAssertEqual(LevelLED.rgb(.nan).red, 0)
        XCTAssertGreaterThan(LevelLED.rgb(0.2).green, 0)
    }
}
