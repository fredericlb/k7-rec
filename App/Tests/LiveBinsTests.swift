// The live well's bins are pinned to take time: when the window moves on by a bucket, every bin both windows
// hold keeps its level, so a bar slides without changing height.
import XCTest
@testable import K7Rec

final class LiveBinsTests: XCTestCase {
    func testABinKeepsItsLevelWhenTheWindowMovesOn() {
        let take = (0..<40).map { Double(($0 * 37) % 11) / 10 }
        let before = Dictionary(uniqueKeysWithValues: LiveBins.levels(Array(take[0..<30]), first: 0, perBin: 3).map { ($0.bucket, $0.level) })
        let after = LiveBins.levels(Array(take[1..<31]), first: 1, perBin: 3)
        for bin in after where bin.bucket >= 3 && bin.bucket + 3 <= 30 {
            XCTAssertEqual(bin.level, before[bin.bucket], "bin at bucket \(bin.bucket)")
        }
        XCTAssertEqual(after.first?.bucket, 0, "bins start on a multiple of their size")
    }

    func testEmptyInputDrawsNothing() {
        XCTAssertTrue(LiveBins.levels([], first: 0, perBin: 2).isEmpty)
        XCTAssertTrue(LiveBins.levels([1], first: 0, perBin: 0).isEmpty)
    }
}
