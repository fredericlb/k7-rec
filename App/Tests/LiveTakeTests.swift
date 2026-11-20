// The live take: re-levelling, the drawn window and the count of moments found so far.
import XCTest
@testable import K7Rec

final class LiveTakeTests: XCTestCase {
    func testTheEnvelopeIsLevelledToItsLoudestBucket() {
        var take = LiveTake()
        for (i, v) in [0.01, 0.02, 0.04].enumerated() { take.append(index: i, sample: v) }
        XCTAssertEqual(take.levelled.max()!, 0.9, accuracy: 1e-9)
        XCTAssertEqual(take.levelled[0], 0.225, accuracy: 1e-9)
    }

    func testABucketOutOfOrderIsIgnored() {
        var take = LiveTake()
        take.append(index: 0, sample: 0.1)
        take.append(index: 0, sample: 0.9)
        take.append(index: 5, sample: 0.9)
        XCTAssertEqual(take.levelled.count, 1)
    }

    func testAYoungTakeDrawsFromTheRightEdgeAndAnOldOneShowsItsEnd() {
        var take = LiveTake()
        for i in 0..<10 { take.append(index: i, sample: 0.5) }
        let young = take.window()
        XCTAssertEqual(young.count, 150)
        XCTAssertEqual(young.prefix(140).max(), 0)
        XCTAssertGreaterThan(young.last!, 0)
        for i in 10..<400 { take.append(index: i, sample: i < 399 ? 0.1 : 0.5) }
        XCTAssertEqual(take.window().count, 150)
        XCTAssertEqual(take.window().last!, 0.9, accuracy: 1e-9)
    }

    func testMomentsAreCountedAsTheTakeGoes() {
        var take = LiveTake()
        var i = 0
        func push(_ seconds: Double, _ v: Double) { for _ in 0..<Int(seconds * 5) { take.append(index: i, sample: v); i += 1 } }
        push(10, 0.5)
        XCTAssertEqual(take.moments, 1)
        push(3, 0.001)
        push(6, 0.5)
        XCTAssertEqual(take.moments, 2)
    }

    func testAContinuedTakeKeepsItsEarlierSamples() {
        var take = LiveTake(base: [0.9, 0.9])
        take.append(index: 0, sample: 0.2)
        XCTAssertEqual(take.levelled.count, 3)
        XCTAssertEqual(take.levelled[0], 0.9)
    }

    func testTheWindowStartPlacesTheDrawnStretchOnTheTakeClock() {
        var take = LiveTake(intervalMs: 100)
        for i in 0..<10 { take.append(index: i, sample: 0.2) }
        XCTAssertEqual(take.windowStart, 1 - LiveTake.windowSeconds, accuracy: 1e-9)
        for i in 10..<400 { take.append(index: i, sample: 0.2) }
        XCTAssertEqual(take.windowStart, 40 - LiveTake.windowSeconds, accuracy: 1e-9)
    }
}
