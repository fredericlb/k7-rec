// TakeRecorderTests.swift: the recorder's logic against a fake input, no microphone and no device.

import AVFoundation
import XCTest
@testable import RehearsalAudio

final class FakeSession: SessionHost, @unchecked Sendable {
  var onInterruption: (@Sendable (InterruptionEvent) -> Void)?
  var activations: [(recording: Bool, headsetInput: Bool)] = []
  var observing = false
  func observe() { observing = true }
  func unobserve() { observing = false }
  func activate(recording: Bool, headsetInput: Bool) throws { activations.append((recording, headsetInput)) }
  func send(_ e: InterruptionEvent) { onInterruption?(e) }
}

final class FakeInput: AudioInput, @unchecked Sendable {
  var sampleRate = 8000.0
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
    XCTAssertEqual(r.appliedGain, 3, accuracy: 0.01)
    XCTAssertEqual(r.envelope.samples.count, 10)
    XCTAssertEqual(r.envelope.peak, 0.9, accuracy: 0.02)
    XCTAssertEqual(try peak(of: r.url), 0.9, accuracy: 0.05)
    XCTAssertEqual(AVAudioFile.lengthSec(r.url), 2, accuracy: 0.15)
    XCTAssertEqual(r.url.pathExtension, "m4a")
    XCTAssertEqual(TakeRecorder.leftovers(in: dir).count, 1)
    r.confirmSaved()
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [r.url.lastPathComponent])
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

  func testAMicrophoneAtZeroHertzRefusesToStartAndSaysWhy() throws {
    let input = FakeInput()
    input.sampleRate = 0
    let rec = TakeRecorder(input: input, directory: dir)
    XCTAssertThrowsError(try rec.start()) { error in
      guard case RecorderError.noInputFormat = error else { return XCTFail("\(error)") }
      XCTAssertTrue(error.localizedDescription.contains("0 Hz"))
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [])
    input.sampleRate = 8000
    XCTAssertNoThrow(try rec.start())
  }

  func testAStuckDeviceAudioSaysToRestart() {
    XCTAssertEqual(RecorderError.ioRefusedCode, 1_852_797_029)
    XCTAssertTrue(RecorderError.audioStuck.localizedDescription.contains("Restart"))
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

  func testAnInterruptionPausesWithAReasonAndOnlyResumeContinues() async throws {
    let input = FakeInput()
    let session = FakeSession()
    let rec = TakeRecorder(input: input, directory: dir, session: session)
    try rec.start()
    input.push(seconds: 1, amp: 0.5)
    session.send(.began)
    XCTAssertEqual(rec.status, .paused)
    XCTAssertEqual(rec.pauseReason, .interrupted)
    XCTAssertFalse(input.running)
    session.send(.ended(shouldResume: true))
    XCTAssertEqual(rec.status, .paused)
    let before = session.activations.count
    try rec.resume()
    XCTAssertEqual(session.activations.count, before + 1)
    XCTAssertEqual(rec.status, .recording)
    XCTAssertNil(rec.pauseReason)
    input.push(seconds: 1, amp: 0.5)
    let r = try await rec.stop()
    XCTAssertEqual(r.durationSec, 2, accuracy: 1e-6)
    XCTAssertFalse(session.observing)
    var lost = 0
    for await e in rec.events where e == .lost { lost += 1 }
    XCTAssertEqual(lost, 1)
  }

  func testAMediaServicesResetPausesToo() throws {
    let input = FakeInput()
    let session = FakeSession()
    let rec = TakeRecorder(input: input, directory: dir, session: session)
    try rec.start()
    session.send(.mediaServicesReset)
    XCTAssertEqual(rec.pauseReason, .interrupted)
  }

  func testAUserPauseIsNotAnInterruption() throws {
    let rec = TakeRecorder(input: FakeInput(), directory: dir, session: FakeSession())
    try rec.start()
    rec.pause()
    XCTAssertEqual(rec.pauseReason, .user)
  }

  func testResumeOnAnotherRateEndsTheTakeButKeepsWhatWasRecorded() async throws {
    let input = FakeInput()
    let rec = TakeRecorder(input: input, directory: dir, session: FakeSession())
    try rec.start()
    input.push(seconds: 1, amp: 0.3)
    rec.pause()
    input.sampleRate = 16_000
    do {
      try rec.resume()
      XCTFail("expected rateChanged")
    } catch RecorderError.rateChanged {}
    XCTAssertFalse(input.running)
    XCTAssertEqual(rec.status, .paused)
    let r = try await rec.stop()
    XCTAssertEqual(r.durationSec, 1, accuracy: 1e-6)
    XCTAssertEqual(AVAudioFile.lengthSec(r.url), 1, accuracy: 0.15)
  }

  func testAFailedStartLeavesTheMicrophoneOff() {
    let input = FakeInput()
    let session = FakeSession()
    let rec = TakeRecorder(input: input, directory: dir.appendingPathComponent("missing"), session: session)
    XCTAssertThrowsError(try rec.start())
    XCTAssertFalse(input.running)
    XCTAssertEqual(rec.status, .idle)
    XCTAssertFalse(session.observing)
  }

  func testRecoverFinishesARawTakeAndTheRawFileGoesOnConfirm() async throws {
    let url = dir.appendingPathComponent("take-x.raw.caf")
    let file = try RawTakeFile(url: url, sampleRate: 8000)
    [Float](repeating: 0.3, count: 8000).withUnsafeBufferPointer { file.append($0) }
    try file.close()
    let r = try await TakeRecorder.recover(raw: url)
    XCTAssertEqual(try peak(of: r.url), 0.9, accuracy: 0.05)
    XCTAssertEqual(r.durationSec, 1, accuracy: 1e-6)
    XCTAssertEqual(r.appliedGain, 3, accuracy: 0.01)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    r.confirmSaved()
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testACrashedContinuationRecoversWithItsEarlierPart() async throws {
    let input = FakeInput()
    var rec: TakeRecorder? = TakeRecorder(input: input, directory: dir, session: FakeSession())
    try rec!.start()
    input.push(seconds: 1, amp: 0.2)
    let a = try await rec!.stop()
    a.confirmSaved()
    rec = TakeRecorder(input: input, directory: dir, session: FakeSession())
    try rec!.start(extending: ExistingTake(url: a.url, envelope: a.envelope))
    input.push(seconds: 1, amp: 0.1)
    rec = nil
    try await Task.sleep(nanoseconds: 200_000_000)
    let raw = try XCTUnwrap(TakeRecorder.leftovers(in: dir).first)
    let r = try await TakeRecorder.recover(raw: raw)
    XCTAssertEqual(r.offsetSec, a.durationSec, accuracy: 1e-6)
    XCTAssertEqual(r.envelope.samples.count, 10)
    XCTAssertEqual(Array(r.envelope.samples[0..<5]), a.envelope.samples)
    r.confirmSaved()
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), [a.url.lastPathComponent, r.url.lastPathComponent].sorted())
  }

  func testContinuingAtAnotherRateJoinsWithoutLosingTheTail() async throws {
    let input = FakeInput()
    let first = TakeRecorder(input: input, directory: dir, session: FakeSession())
    try first.start()
    input.push(seconds: 1, amp: 0.3)
    let a = try await first.stop()
    input.sampleRate = 16_000
    let second = TakeRecorder(input: input, directory: dir, session: FakeSession())
    try second.start(extending: ExistingTake(url: a.url, envelope: a.envelope))
    input.push(seconds: 1, amp: 0.3)
    let b = try await second.stop()
    XCTAssertEqual(AVAudioFile.lengthSec(b.url), 2, accuracy: 0.03)
  }

  func testACrashRightAfterAContinuationRecoversTheEarlierPart() async throws {
    let input = FakeInput()
    let first = TakeRecorder(input: input, directory: dir, session: FakeSession())
    try first.start()
    input.push(seconds: 1, amp: 0.3)
    let a = try await first.stop()
    var second: TakeRecorder? = TakeRecorder(input: input, directory: dir, session: FakeSession())
    try second!.start(extending: ExistingTake(url: a.url, envelope: a.envelope))
    a.confirmSaved()
    second = nil
    try await Task.sleep(nanoseconds: 200_000_000)

    let raw = try XCTUnwrap(TakeRecorder.leftovers(in: dir).first)
    let r = try await TakeRecorder.recover(raw: raw)

    XCTAssertEqual(r.url, a.url)
    XCTAssertEqual(r.durationSec, a.durationSec, accuracy: 1e-6)
    XCTAssertEqual(r.envelope.samples, a.envelope.samples)
    r.confirmSaved()
    XCTAssertTrue(TakeRecorder.leftovers(in: dir).isEmpty)
    XCTAssertTrue(FileManager.default.fileExists(atPath: a.url.path))
  }
}
