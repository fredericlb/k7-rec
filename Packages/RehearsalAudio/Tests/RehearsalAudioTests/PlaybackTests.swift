// PlaybackTests.swift: the playhead, the one-at-a-time rule, the click, and a player rendered offline.

import AVFoundation
import XCTest
@testable import RehearsalAudio

@MainActor
private final class Fake: PlaybackYielding {
  var yielded = 0
  func yieldPlayback() { yielded += 1 }
}

@MainActor
final class PlaybackTests: XCTestCase {
  func testPlayheadAdvancesThenLoopsFromTheRangeStart() {
    func at(_ played: Int, loops: Bool) -> Int {
      Playhead.frame(from: 150, rangeStart: 100, rangeEnd: 200, loops: loops, played: played)
    }
    XCTAssertEqual(at(10, loops: true), 160)
    XCTAssertEqual(at(60, loops: true), 110)
    XCTAssertEqual(at(250, loops: true), 100)
    XCTAssertEqual(at(60, loops: false), 200)
  }

  func testClaimingTheFloorYieldsTheOneThatHeldIt() {
    let c = PlaybackCoordinator()
    let a = Fake()
    let b = Fake()
    c.claim(a)
    c.claim(a)
    XCTAssertEqual(a.yielded, 0)
    c.claim(b)
    XCTAssertEqual(a.yielded, 1)
    c.release(b)
    c.claim(a)
    XCTAssertEqual(b.yielded, 0)
  }

  func testClickGeneratorPutsABeatEveryPeriodAndAnAccentEveryFourth() {
    var g = ClickGenerator(bpm: 120, sampleRate: 8000)
    var out = [Float](repeating: 0, count: 8000 * 4)
    let beats = out.withUnsafeMutableBufferPointer { g.render(into: $0.baseAddress!, frames: 8000 * 4) }
    XCTAssertEqual(beats.count, 8)
    XCTAssertEqual(beats[0].frame, 400)
    XCTAssertEqual(beats[1].frame - beats[0].frame, 4000)
    XCTAssertEqual(beats.map(\.downbeat), [true, false, false, false, true, false, false, false])
    XCTAssertEqual(out[0], 0)
    XCTAssertGreaterThan(out[400..<480].map { abs($0) }.max()!, 0.3)
    XCTAssertEqual(out[400 + 500], 0)
  }

  func testClickIsTheSameWhateverTheBufferSize() {
    var a = ClickGenerator(bpm: 100, sampleRate: 8000)
    var b = ClickGenerator(bpm: 100, sampleRate: 8000)
    var whole = [Float](repeating: 0, count: 6000)
    _ = whole.withUnsafeMutableBufferPointer { a.render(into: $0.baseAddress!, frames: 6000) }
    var parts = [Float](repeating: 0, count: 6000)
    parts.withUnsafeMutableBufferPointer { p in
      var off = 0
      while off < 6000 {
        let n = min(477, 6000 - off)
        _ = b.render(into: p.baseAddress! + off, frames: n)
        off += n
      }
    }
    XCTAssertEqual(whole, parts)
  }

  private func offlinePlayer(seconds: Double, session: SessionHost = FakeSession()) throws -> (TakePlayer, AVAudioEngine) {
    let url = try TestAudio.wav(seconds: seconds, amp: 0.5)
    let engine = AVAudioEngine()
    try engine.enableManualRenderingMode(.offline, format: AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 2)!, maximumFrameCount: 4096)
    return (try TakePlayer(url: url, engine: engine, coordinator: PlaybackCoordinator(), session: session), engine)
  }

  private func render(_ engine: AVAudioEngine, frames: AVAudioFrameCount) throws {
    let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: frames)!
    XCTAssertEqual(try engine.renderOffline(frames, to: buf), .success)
  }

  func testPlayerPlaysPausesAndSeeks() throws {
    let (p, e) = try offlinePlayer(seconds: 2)
    try p.play()
    try render(e, frames: 4000)
    XCTAssertEqual(p.positionSec, 0.5, accuracy: 0.1)
    p.pause()
    let held = p.positionSec
    try render(e, frames: 2000)
    XCTAssertEqual(p.positionSec, held, accuracy: 1e-9)
    p.seek(to: 1.5)
    XCTAssertEqual(p.positionSec, 1.5, accuracy: 1e-3)
    XCTAssertEqual(p.state, .paused)
  }

  func testAnInterruptionPausesThePlayerWhereItStood() throws {
    let session = FakeSession()
    let (p, e) = try offlinePlayer(seconds: 2, session: session)
    try p.play()
    try render(e, frames: 4000)
    session.send(.began)
    XCTAssertEqual(p.state, .paused)
    XCTAssertEqual(p.positionSec, 0.5, accuracy: 0.1)
    try p.play()
    XCTAssertEqual(p.state, .playing)
  }

  func testAnEngineReconfigurationPausesThePlayer() async throws {
    let (p, e) = try offlinePlayer(seconds: 2)
    try p.play()
    try render(e, frames: 2000)
    NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: e)
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(p.state, .paused)
  }

  func testAnInterruptionStopsTheMetronome() throws {
    let session = FakeSession()
    let m = Metronome(session: session)
    try m.start(bpm: 120, startSec: 0)
    XCTAssertNotNil(m.state)
    session.send(.began)
    XCTAssertNil(m.state)
  }

  func testPlayerLoopsItsRange() throws {
    let (p, e) = try offlinePlayer(seconds: 2)
    p.setRange(0.5...0.75, loops: true)
    try p.play()
    try render(e, frames: 4096)
    try render(e, frames: 4096)
    XCTAssertEqual(p.state, .playing)
    XCTAssertGreaterThanOrEqual(p.positionSec, 0.5)
    XCTAssertLessThanOrEqual(p.positionSec, 0.75)
  }

  func testPlayerStopsAtTheEndOfARange() async throws {
    let (p, e) = try offlinePlayer(seconds: 2)
    p.completionType = .dataConsumed
    var finished = false
    p.onFinish = { finished = true }
    p.setRange(0.5...0.6)
    try p.play()
    try render(e, frames: 4096)
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertTrue(finished)
    XCTAssertEqual(p.state, .stopped)
    XCTAssertEqual(p.positionSec, 0.6, accuracy: 1e-3)
  }

  func testGainIsCappedAtTheEQsRange() {
    XCTAssertEqual(TakePlayer.decibels(1), 0, accuracy: 1e-6)
    XCTAssertEqual(TakePlayer.decibels(2), 6.02, accuracy: 0.01)
    XCTAssertEqual(TakePlayer.decibels(32), 24)
  }
}
