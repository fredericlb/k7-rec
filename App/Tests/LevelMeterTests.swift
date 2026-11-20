// The input level follows decibels: the bar is empty at -40 dB and full at full level; the rec tint goes from
// clear to green, orange and red on the same scale.
import XCTest
@testable import K7Rec

final class LevelMeterTests: XCTestCase {
    func testTheBarFollowsDecibels() {
        XCTAssertEqual(LevelMeter.position(0.005), 0)
        XCTAssertEqual(LevelMeter.position(0.1), 0.5, accuracy: 0.001)
        XCTAssertEqual(LevelMeter.position(1), 1)
        XCTAssertGreaterThan(LevelMeter.position(0.02), 0.1)
    }

    func testBadLevelsAreEmptyAndLoudOnesStayFull() {
        XCTAssertEqual(LevelMeter.position(5), 1)
        XCTAssertEqual(LevelMeter.position(-1), 0)
        XCTAssertEqual(LevelMeter.position(.nan), 0)
    }

    func testTheTintIsClearAtSilenceThenGreenOrangeRed() {
        XCTAssertEqual(LevelMeter.tint(0.005).alpha, 0)
        let green = LevelMeter.tint(0.1)
        XCTAssertGreaterThan(green.green, green.red)
        XCTAssertEqual(green.alpha, 0.8, accuracy: 0.001)
        let orange = LevelMeter.tint(pow(10, -6.0 / 20))
        XCTAssertEqual(orange.red, 1, accuracy: 0.001)
        XCTAssertEqual(orange.green, 0.6, accuracy: 0.001)
        let red = LevelMeter.tint(1)
        XCTAssertEqual(red.red, 1)
        XCTAssertLessThan(red.green, 0.2)
        XCTAssertLessThan(LevelMeter.tint(0.02).alpha, 0.8, "a quiet room is a faint tint")
    }

    func testTheMeterRisesFastAndFallsSlowly() {
        let up = LevelMeter.follow(0, toward: 1)
        let down = LevelMeter.follow(1, toward: 0)
        XCTAssertEqual(up, 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(down, 0.8, "a drop shows over several steps")
        var p = 0.0
        for _ in 0..<3 { p = LevelMeter.follow(p, toward: 1) }
        XCTAssertGreaterThan(p, 0.85, "a peak shows within 150 ms")
    }
}
