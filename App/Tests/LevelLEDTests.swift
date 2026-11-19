// The rec button's LED colour: black at silence, green at -20 dB, orange at -6 dB, red at full level.
import XCTest
@testable import Rehearsal

final class LevelLEDTests: XCTestCase {
    func testTheLEDFollowsDecibelsBlackGreenOrangeRed() {
        let black = LevelLED.rgb(0.005)
        XCTAssertEqual(black.red + black.green + black.blue, 0)
        let green = LevelLED.rgb(0.1)
        XCTAssertEqual(green.green, 0.85, accuracy: 0.001)
        XCTAssertGreaterThan(green.green, green.red)
        let orange = LevelLED.rgb(pow(10, -6.0 / 20))
        XCTAssertEqual(orange.red, 1, accuracy: 0.001)
        XCTAssertEqual(orange.green, 0.6, accuracy: 0.001)
        XCTAssertEqual(LevelLED.rgb(1).red, 1)
        XCTAssertLessThan(LevelLED.rgb(1).green, 0.2)
    }

    func testAQuietRoomAlreadyGlowsAndBadLevelsAreDark() {
        XCTAssertGreaterThan(LevelLED.rgb(0.02).green, 0.2)
        XCTAssertEqual(LevelLED.rgb(5).green, LevelLED.rgb(1).green)
        XCTAssertEqual(LevelLED.rgb(-1).red, 0)
        XCTAssertEqual(LevelLED.rgb(.nan).red, 0)
    }
}
