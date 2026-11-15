// PureTests.swift: the envelope, the moment detector, the gain and the clock, all without a device.

import XCTest
@testable import RehearsalAudio

final class PureTests: XCTestCase {
  // dt = 0.2 s, so 5 samples a second.
  private func env(_ runs: [(Double, Double)]) -> Envelope {
    var s: [Double] = []
    for (level, sec) in runs { s += Array(repeating: level, count: Int(sec * 5)) }
    return Envelope(samples: s)
  }

  func testDetectFindsLongMomentsAndDropsBlips() {
    let e = env([(0.5, 10), (0, 3), (0.4, 6), (0, 3), (0.5, 1)])
    let r = MomentDetector.detect(envelope: e)
    XCTAssertEqual(r.peak, 0.5)
    XCTAssertEqual(r.floor, 0.075, accuracy: 1e-12)
    XCTAssertEqual(r.moments.count, 2)
    XCTAssertEqual(r.moments[0].startSec, 0)
    XCTAssertEqual(r.moments[0].endSec, 10)
    XCTAssertEqual(r.moments[0].durationSec, 10)
    XCTAssertEqual(r.moments[0].avg, 0.5)
    XCTAssertEqual(r.moments[1].startSec, 13)
    XCTAssertEqual(r.moments[1].endSec, 19)
    XCTAssertEqual(r.moments[1].avg, 0.4)
  }

  func testShortDipDoesNotCutAMoment() {
    let e = env([(0.5, 6), (0, 1), (0.5, 6)])
    let r = MomentDetector.detect(envelope: e)
    XCTAssertEqual(r.moments.count, 1)
    XCTAssertEqual(r.moments[0].durationSec, 13)
  }

  func testFloorOverrideAndSilenceOption() {
    let e = env([(0.5, 6), (0.1, 3), (0.5, 6)])
    XCTAssertEqual(MomentDetector.detect(envelope: e, floor: 0.3).moments.count, 2)
    XCTAssertEqual(MomentDetector.detect(envelope: e, floor: 0.3, silence: 4).moments.count, 1)
  }

  func testEmptyAndSilentEnvelopeFindNothing() {
    XCTAssertEqual(MomentDetector.detect(envelope: Envelope()).moments, [])
    let silent = MomentDetector.detect(envelope: env([(0, 10)]), silence: 3)
    XCTAssertEqual(silent.floor, 0)
    XCTAssertEqual(silent.silence, 3)
    XCTAssertEqual(silent.moments, [])
  }

  func testMomentAtTheEndIsClosed() {
    let r = MomentDetector.detect(envelope: env([(0, 3), (0.5, 5)]))
    XCTAssertEqual(r.moments.map(\.startSec), [3])
    XCTAssertEqual(r.moments.map(\.endSec), [8])
  }

  func testBuilderBucketsRMSAcrossChunkBoundaries() {
    var b = EnvelopeBuilder(sampleRate: 1000, intervalMs: 200)
    let sq = [Float](repeating: 0.5, count: 700)
    b.feed(Array(sq[0..<150]))
    b.feed(Array(sq[150..<700]))
    XCTAssertEqual(b.samples, [0.5, 0.5, 0.5])
    let done = b.finish()
    XCTAssertEqual(done.samples.count, 4)
    XCTAssertEqual(done.durationSec, 0.8, accuracy: 1e-9)
  }

  func testBuilderRMSOfASine() {
    var b = EnvelopeBuilder(sampleRate: 8000, intervalMs: 200)
    b.feed((0..<8000).map { Float(sin(2 * Double.pi * 100 * Double($0) / 8000)) })
    XCTAssertEqual(b.samples.count, 5)
    for s in b.samples { XCTAssertEqual(s, 0.7071, accuracy: 0.001) }
  }

  func testLiveEnvelopeAppendsAtGainAndKeepsBase() {
    var live = LiveEnvelope(base: [0.1, 0.2])
    XCTAssertEqual(live.offsetSec, 0.4, accuracy: 1e-12)
    live.pull(raw: [0.1, 0.4], gain: 2)
    live.pull(raw: [0.1, 0.4, 0.6], gain: 2)
    XCTAssertEqual(live.envelope.samples, [0.1, 0.2, 0.2, 0.8, 1])
    XCTAssertEqual(live.peak, 1)
  }

  func testGainTargetsNinetyPercentAndCaps() {
    XCTAssertEqual(Gain.envelope(rawPeak: 0.45), 2, accuracy: 1e-12)
    XCTAssertEqual(Gain.envelope(rawPeak: 0.0001), 32)
    XCTAssertEqual(Gain.envelope(rawPeak: 0), 32)
    XCTAssertEqual(Gain.playback(truePeak: 0.3), 3, accuracy: 1e-12)
    XCTAssertEqual(Gain.playback(truePeak: 0), 1)
    XCTAssertEqual(Gain.playback(truePeak: 0.001), 32)
  }

  func testScaledCapsAndRounds() {
    let s = Envelope(samples: [0.12345, 0.9]).scaled(by: 2)
    XCTAssertEqual(s.samples, [0.2469, 1])
  }

  func testFmtTime() {
    XCTAssertEqual(fmtTime(0), "0:00")
    XCTAssertEqual(fmtTime(65.9), "1:05")
    XCTAssertEqual(fmtTime(3600), "1:00:00")
    XCTAssertEqual(fmtTime(3725), "1:02:05")
    XCTAssertEqual(fmtTime(-3), "0:00")
    XCTAssertEqual(fmtTime(.infinity), "0:00")
    XCTAssertEqual(fmtTime(.nan), "0:00")
  }

  func testDatesFollowTheLocalePassed() {
    var c = DateComponents(year: 2026, month: 10, day: 27, hour: 13, minute: 13, second: 26)
    c.calendar = Calendar(identifier: .gregorian)
    let at = c.date!
    let en = Locale(identifier: "en_US")
    let fr = Locale(identifier: "fr_FR")
    XCTAssertEqual(formatDate(at, .day, locale: en), "Tuesday, October 27, 2026")
    XCTAssertTrue(formatDate(at, .day, locale: fr).contains("27 octobre 2026"))
    XCTAssertTrue(formatDate(at, .stamp, locale: fr).contains("13:13"))
    XCTAssertTrue(formatDate(at, .stamp, locale: en).contains("Oct 27"))
    XCTAssertEqual(formatDate(iso: "not a date", .day, locale: en), "")
  }
}
