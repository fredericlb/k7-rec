// EnvelopeReaderTests.swift: the offline envelope of generated files.

import XCTest
@testable import RehearsalAudio

final class EnvelopeReaderTests: XCTestCase {
  func testSineHasRMSOfAmpOverRootTwo() throws {
    let url = try TestAudio.wav(seconds: 2, amp: 0.5)
    let r = try EnvelopeReader.read(url: url)
    XCTAssertEqual(r.envelope.samples.count, 10)
    XCTAssertEqual(r.durationSec, 2, accuracy: 1e-6)
    for s in r.envelope.samples { XCTAssertEqual(s, 0.3536, accuracy: 0.002) }
    XCTAssertEqual(r.truePeak, 0.5, accuracy: 0.01)
  }

  func testSilenceReadsZero() throws {
    let r = try EnvelopeReader.read(url: try TestAudio.wav(seconds: 1, amp: 0))
    XCTAssertEqual(r.envelope.samples, [0, 0, 0, 0, 0])
    XCTAssertEqual(r.truePeak, 0)
  }

  func testStereoIsAveragedAndPartialBucketKept() throws {
    let r = try EnvelopeReader.read(url: try TestAudio.wav(seconds: 0.5, amp: 0.4, channels: 2))
    XCTAssertEqual(r.envelope.samples.count, 3)
    XCTAssertEqual(r.envelope.samples[0], 0.2828, accuracy: 0.002)
  }
}
