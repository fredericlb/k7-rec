// The backdrop's waves: a slow drift in opposite directions when silent; with sound they grow with the level and
// speed up, and settle back once it stops.
import XCTest
@testable import K7Rec

final class WaveClockTests: XCTestCase {
    private func run(_ clock: WaveClock, seconds: Double, level: Double?, from start: Date) -> (WaveClock.State, Date) {
        var t = start, s = WaveClock.State()
        for _ in 0..<Int(seconds * 30) { t += 1.0 / 30; s = clock.step(at: t, level: level) }
        return (s, t)
    }

    func testSilentWavesDriftSlowlyApart() {
        let clock = WaveClock()
        _ = clock.step(at: Date(timeIntervalSince1970: 0), level: nil)
        let (s, _) = run(clock, seconds: 6, level: nil, from: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(s.phase1, 6 / 60, accuracy: 0.002)
        XCTAssertEqual(s.phase2, -6 / 90, accuracy: 0.002)
        XCTAssertEqual(s.scale, 1)
    }

    func testSoundSpeedsThemUpAndALoudLevelDoublesTheirHeight() {
        let clock = WaveClock()
        let start = Date(timeIntervalSince1970: 0)
        _ = clock.step(at: start, level: 1)
        let (before, t) = run(clock, seconds: 4, level: 1, from: start)
        let (after, _) = run(clock, seconds: 1, level: 1, from: t)
        XCTAssertEqual(after.phase1 - before.phase1, 1 / 9, accuracy: 0.01, "one pass in 9 s with sound")
        XCTAssertEqual(after.scale, 2, accuracy: 0.01)
    }

    func testTheyBreatheBackWhenSoundStops() {
        let clock = WaveClock()
        let start = Date(timeIntervalSince1970: 0)
        _ = clock.step(at: start, level: 1)
        let (_, t) = run(clock, seconds: 2, level: 1, from: start)
        let (quickly, t2) = run(clock, seconds: 0.2, level: nil, from: t)
        XCTAssertGreaterThan(quickly.scale, 1.4, "the height settles, it does not drop")
        let (settled, _) = run(clock, seconds: 4, level: nil, from: t2)
        XCTAssertEqual(settled.scale, 1, accuracy: 0.01)
        XCTAssertLessThan(clock.busy, 0.01)
    }

    func testAWaveIsOnePeriodAcrossTheWidth() {
        for w in [WaveShape.first, .second] { XCTAssertEqual(w.y(0, scale: 1), w.y(1, scale: 1), accuracy: 1e-9) }
        XCTAssertEqual(WaveShape.first.y(0, scale: 1), 80.2, accuracy: 0.1, "matches the design system's line")
    }
}
