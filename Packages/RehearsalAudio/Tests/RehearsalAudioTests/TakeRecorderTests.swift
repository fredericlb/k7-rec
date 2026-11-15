// TakeRecorderTests.swift: the recorder's logic against a fake input, no microphone and no device.

import AVFoundation
import XCTest
@testable import RehearsalAudio

final class FakeInput: AudioInput, @unchecked Sendable {
  let sampleRate = 8000.0
  var onLost: (@Sendable () -> Void)?
  var handler: (@Sendable (UnsafeBufferPointer<Float>) -> Void)?
  var running = false
  func start(_ onFrames: @escaping @Sendable (UnsafeBufferPointer<Float>) -> Void) throws {
    handler = onFrames
    running = true
  }
  func stop() { running = false }
  /// What the hardware would deliver; nothing is delivered while stopped.
  func push(seconds: Double, amp: Float) {
    guard running, let handler else { return }
    let n = Int(seconds * sampleRate)
    let v = (0..<n).map { amp * Float(sin(2 * Double.pi * 220 * Double($0) / sampleRate)) }
    v.withUnsafeBufferPointer { handler($0) }
  }
}

final class TakeRecorderTests: XCTestCase {
  private var dir: URL!
  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: dir) }

  private func peak(of url: URL) throws -> Double {
    try EnvelopeReader.read(url: url).truePeak
  }

  func testPauseResumeKeepsOneTakeAndNormalisesToNinetyPercent() async throws {
    let input = FakeInput()
    let rec = TakeRecorder(input: input, directory: dir)
    try rec.start()
    input.push(seconds: 1, amp: 0.3)
    rec.pause()
    XCTAssertEqual(rec.status, .paused)
    input.push(seconds: 5, amp: 0.3)
    try rec.resume()
    input.push(seconds: 1, amp: 0.3)
    XCTAssertEqual(rec.elapsedSec, 2, accuracy: 1e-6)
    let r = try await rec.stop()
    XCTAssertEqual(r.durationSec, 2, accuracy: 1e-6)
    XCTAssertEqual(r.gain, 3, accuracy: 0.01)
    XCTAssertEqual(r.envelope.samples.count, 10)
    XCTAssertEqual(r.envelope.peak, 0.9, accuracy: 0.02)
    XCTAssertEqual(try peak(of: r.url), 0.9, accuracy: 0.05)
    XCTAssertEqual(AVAudioFile.lengthSec(r.url), 2, accuracy: 0.15)
    XCTAssertEqual(r.url.pathExtension, "m4a")
    XCTAssertTrue(TakeRecorder.leftovers(in: dir).isEmpty)
  }

  func testEventsCarryLevelsAndEnvelopeBuckets() async throws {
    let input = FakeInput()
    let rec = TakeRecorder(input: input, directory: dir)
    try rec.start()
    input.push(seconds: 0.5, amp: 0.5)
    _ = try await rec.stop()
    var buckets = 0
    var levels = 0
    for await e in rec.events {
      if case .envelope(_, let s) = e { buckets += 1; XCTAssertEqual(s, 0.3536, accuracy: 0.003) }
      if case .level = e { levels += 1 }
    }
    XCTAssertEqual(buckets, 2)
    XCTAssertEqual(levels, 1)
  }

  func testExtendingJoinsTheEarlierFileAndItsEnvelope() async throws {
    let input = FakeInput()
    let first = TakeRecorder(input: input, directory: dir)
    try first.start()
    input.push(seconds: 1, amp: 0.2)
    let a = try await first.stop()
    let second = TakeRecorder(input: input, directory: dir)
    try second.start(extending: ExistingTake(url: a.url, envelope: a.envelope))
    input.push(seconds: 1, amp: 0.1)
    let b = try await second.stop()
    XCTAssertEqual(b.offsetSec, a.durationSec, accuracy: 1e-6)
    XCTAssertEqual(b.durationSec, 2, accuracy: 0.2)
    XCTAssertEqual(b.envelope.samples.count, 10)
    XCTAssertEqual(Array(b.envelope.samples[0..<5]), a.envelope.samples)
    XCTAssertEqual(AVAudioFile.lengthSec(b.url), b.durationSec, accuracy: 0.2)
  }

  func testLostInputPausesAndSaysSo() async throws {
    let input = FakeInput()
    let rec = TakeRecorder(input: input, directory: dir)
    try rec.start()
    input.push(seconds: 1, amp: 0.5)
    input.onLost?()
    XCTAssertEqual(rec.status, .paused)
    let r = try await rec.stop()
    XCTAssertEqual(r.durationSec, 1, accuracy: 1e-6)
    var lost = false
    for await e in rec.events where e == .lost { lost = true }
    XCTAssertTrue(lost)
  }

  func testStoppingWithNothingRecordedThrowsAndLeavesNoFile() async throws {
    let input = FakeInput()
    let rec = TakeRecorder(input: input, directory: dir)
    try rec.start()
    do {
      _ = try await rec.stop()
      XCTFail("expected nothingRecorded")
    } catch RecorderError.nothingRecorded {}
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [])
  }

  func testDiscardRemovesTheRawFile() throws {
    let input = FakeInput()
    let rec = TakeRecorder(input: input, directory: dir)
    try rec.start()
    input.push(seconds: 1, amp: 0.5)
    rec.discard()
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [])
  }

  func testCrashLeavesTheRawTakeToBeFound() throws {
    let input = FakeInput()
    let rec = TakeRecorder(input: input, directory: dir)
    try rec.start()
    input.push(seconds: 1, amp: 0.5)
    Thread.sleep(forTimeInterval: 0.2)
    XCTAssertEqual(TakeRecorder.leftovers(in: dir).count, 1)
  }
}
