// The memory note: shown under the threshold, silent at and above it.
import XCTest
@testable import K7Rec

final class StemAdviceTests: XCTestCase {
    func testASmallDeviceGetsANoteAndABigOneDoesNot() {
        XCTAssertNotNil(StemAdvice.memoryNote(physical: 3_000_000_000))
        XCTAssertNil(StemAdvice.memoryNote(physical: 3_800_000_000))
        XCTAssertNil(StemAdvice.memoryNote(physical: StemAdvice.comfortableMemory))
    }
}
