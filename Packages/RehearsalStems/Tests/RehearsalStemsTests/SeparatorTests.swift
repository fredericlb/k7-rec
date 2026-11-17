// SeparatorTests.swift: the segmenting, the cross-fade, the files written and the mix, with a model that is a few lines of code.

import AVFoundation
import XCTest
@testable import RehearsalStems

/// A model that gives `shares[s]` of the input to stem s; the shares sum to one.
struct ShareModel: SegmentModel {
  var sampleRate = 8000.0
  var segmentFrames = 4000
  var shares: [Float] = [0.5, 0.25, 0.25, 0]
  func separate(_ mix: [[Float]]) throws -> [[[Float]]] { shares.map { k in mix.map { $0.map { $0 * k } } } }
}

final class Latest: @unchecked Sendable {
  private let lock = NSLock()
  private var stored = 0.0
  var value: Double { lock.withLock { stored } }
  func set(_ v: Double) { lock.withLock { stored = v } }
}

final class SeparatorTests: XCTestCase {
  private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("stems-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func sine(seconds: Double, rate: Double, channels: Int, in dir: URL) throws -> URL {
    let url = dir.appendingPathComponent("src.wav")
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(channels), interleaved: false)!
    let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 16])
    let n = AVAudioFrameCount(seconds * rate)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
    buf.frameLength = n
    for c in 0..<channels { for i in 0..<Int(n) { buf.floatChannelData![c][i] = 0.5 * Float(sin(2 * Double.pi * 220 * Double(i) / rate)) } }
    try file.write(from: buf)
    return url
  }

  private func samples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
  }

  /// The best-aligned error of `a` against `scale * b`, as a share of b's RMS; AAC delays and smears a little.
  private func relativeError(_ a: [Float], _ b: [Float], scale: Float) -> Float {
    var best = Float.greatestFiniteMagnitude
    for lag in stride(from: 0, to: 2200, by: 1) {
      let n = min(a.count - lag, b.count, 6000) - 200
      guard n > 1000 else { continue }
      var e: Float = 0, r: Float = 0
      for i in 100..<n { let d = a[i + lag] - scale * b[i]; e += d * d; r += (scale * b[i]) * (scale * b[i]) }
      best = min(best, (e / max(r, 1e-9)).squareRoot())
    }
    return best
  }

  func testWritesFourStemsThatCarryTheirShareOfTheInput() async throws {
    let dir = try tempDir()
    let src = try sine(seconds: 3.7, rate: 8000, channels: 2, in: dir)
    let out = dir.appendingPathComponent("stems")
    let last = Latest()
    try await StemSeparator(model: ShareModel(), overlapSeconds: 0.1).separate(source: src, into: out) { last.set($0) }
    XCTAssertEqual(last.value, 1)
    let found = try XCTUnwrap(Stem.existing(in: dir))
    XCTAssertEqual(found.count, 4)
    let original = try samples(src)
    let drums = try samples(found[.drums]!)
    XCTAssertEqual(Double(drums.count), Double(original.count), accuracy: 2300)
    XCTAssertLessThan(relativeError(drums, original, scale: 0.5), 0.15)
    XCTAssertLessThan(relativeError(try samples(found[.bass]!), original, scale: 0.25), 0.15)
    XCTAssertLessThan(try samples(found[.vocals]!).map(abs).max() ?? 1, 0.02)
  }

  func testAMonoFileAtAnotherRateComesOutAtTheModelRate() async throws {
    let dir = try tempDir()
    let src = try sine(seconds: 2, rate: 22_050, channels: 1, in: dir)
    try await StemSeparator(model: ShareModel(), overlapSeconds: 0.1).separate(source: src, into: dir.appendingPathComponent("stems"))
    let file = try AVAudioFile(forReading: Stem.existing(in: dir)![.drums]!)
    XCTAssertEqual(file.processingFormat.sampleRate, 8000)
    XCTAssertEqual(file.processingFormat.channelCount, 2)
    XCTAssertEqual(Double(file.length), 16_000, accuracy: 2300)
  }

  func testAFileShorterThanASegmentStillSeparates() async throws {
    let dir = try tempDir()
    let src = try sine(seconds: 0.2, rate: 8000, channels: 2, in: dir)
    try await StemSeparator(model: ShareModel(), overlapSeconds: 0.1).separate(source: src, into: dir.appendingPathComponent("stems"))
    XCTAssertNotNil(Stem.existing(in: dir))
  }

  func testAModelWithTheWrongStemCountFailsAndLeavesNothing() async throws {
    let dir = try tempDir()
    let src = try sine(seconds: 1, rate: 8000, channels: 2, in: dir)
    let model = ShareModel(shares: [1, 0])
    do {
      try await StemSeparator(model: model).separate(source: src, into: dir.appendingPathComponent("stems"))
      XCTFail("two stems is not a stem set")
    } catch { XCTAssertEqual(error as? StemError, .wrongStemCount(2)) }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["src.wav"])
  }

  func testACancelledRunKeepsTheOldSetAndLeavesNoPartialFolder() async throws {
    let dir = try tempDir()
    let src = try sine(seconds: 6, rate: 8000, channels: 2, in: dir)
    let out = dir.appendingPathComponent("stems")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: out.appendingPathComponent("marker"))
    let task = Task { try await StemSeparator(model: ShareModel(), overlapSeconds: 0.1).separate(source: src, into: out) }
    task.cancel()
    _ = try? await task.value
    XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent("marker").path))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["src.wav", "stems"])
  }

  func testTheCrossfadeOfEqualSignalsIsThatSignal() {
    let held: [[Float]] = [[1, 1, 1, 1], [2, 2, 2, 2]]
    let mixed = StemSeparator.crossfade(held: held, head: held, overlap: 4)
    XCTAssertEqual(mixed, held)
  }

  func testAFolderWithAMissingStemIsNoSet() throws {
    let dir = try tempDir()
    let stems = Stem.folder(in: dir)
    try FileManager.default.createDirectory(at: stems, withIntermediateDirectories: true)
    for s in Stem.allCases.dropLast() { try Data().write(to: stems.appendingPathComponent(s.fileName)) }
    XCTAssertNil(Stem.existing(in: dir))
  }

  func testASoloSilencesTheOthersAndOverridesAMute() {
    var mix = StemMix()
    mix.toggleMute(.drums)
    XCTAssertEqual(mix.gain(of: .drums), 0)
    XCTAssertEqual(mix.gain(of: .bass), 1)
    mix.toggleSolo(.drums)
    XCTAssertEqual(mix.gain(of: .drums), 1)
    XCTAssertEqual(mix.gain(of: .bass), 0)
    mix.toggleSolo(.drums)
    mix.setLevel(0.4, of: .bass)
    XCTAssertEqual(mix.gain(of: .bass), 0.4)
    mix.setLevel(3, of: .bass)
    XCTAssertEqual(mix.level(of: .bass), 1)
  }
}
