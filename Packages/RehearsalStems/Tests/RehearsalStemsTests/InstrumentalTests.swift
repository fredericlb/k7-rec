// InstrumentalTests.swift: the instrumental is the three non-vocal stems summed, and no file is left by a failure.

import AVFoundation
import XCTest
@testable import RehearsalStems

final class InstrumentalTests: XCTestCase {
  private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("inst-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  /// A stem whose two channels hold a sine of the given amplitude.
  private func stem(_ s: Stem, amplitude: Float, in dir: URL) throws -> URL {
    let url = dir.appendingPathComponent(s.fileName)
    let w = try StemWriter(url: url, rate: 8000)
    let wave = (0..<24_000).map { amplitude * sin(Float($0) * 0.1) }
    try w.write([wave, wave])
    return url
  }

  private func rms(_ url: URL) throws -> Float {
    let f = try AVAudioFile(forReading: url)
    let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
    try f.read(into: b)
    let p = UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength))
    return (p.reduce(0) { $0 + $1 * $1 } / Float(max(1, p.count))).squareRoot()
  }

  func testTheVoiceIsLeftOutAndTheRestIsSummed() throws {
    let dir = try tempDir()
    var stems: [Stem: URL] = [:]
    for (s, a) in [(Stem.drums, Float(0.1)), (.bass, 0.1), (.other, 0.1), (.vocals, 0.4)] { stems[s] = try stem(s, amplitude: a, in: dir) }
    let out = dir.appendingPathComponent("instrumental.m4a")
    try InstrumentalMix.write(from: stems, to: out)
    // Three sines of 0.1 in phase make 0.3, RMS 0.3 / sqrt 2; the vocals' 0.4 would have made 0.7.
    XCTAssertEqual(try rms(out), Float(0.3 / 2.0.squareRoot()), accuracy: 0.04)
    XCTAssertEqual(Double(try AVAudioFile(forReading: out).length), 24_000, accuracy: 3_000)
  }

  func testAMissingStemLeavesNoFile() throws {
    let dir = try tempDir()
    let stems: [Stem: URL] = [.drums: try stem(.drums, amplitude: 0.1, in: dir)]
    let out = dir.appendingPathComponent("instrumental.m4a")
    XCTAssertThrowsError(try InstrumentalMix.write(from: stems, to: out))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("instrumental") }, [])
  }

  func testASeparationLeavesTheInstrumentalBesideTheStems() async throws {
    let dir = try tempDir()
    let src = dir.appendingPathComponent("song.wav")
    do {
      let f = try AVAudioFile(forWriting: src, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 8000.0, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16])
      let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 16_000)!
      b.frameLength = 16_000
      for c in 0..<2 { for i in 0..<16_000 { b.floatChannelData![c][i] = 0.5 * sin(Float(i) * 0.1) } }
      try f.write(from: b)
    }
    try await StemSeparator(model: ShareModel(), overlapSeconds: 0.1).separate(source: src, into: dir.appendingPathComponent("stems"))
    let mix = InstrumentalMix.url(in: dir)
    XCTAssertTrue(FileManager.default.fileExists(atPath: mix.path))
    // ShareModel gives the voice nothing, so the instrumental is the source at full level.
    XCTAssertEqual(try rms(mix), Float(0.5 / 2.0.squareRoot()), accuracy: 0.05)
  }
}
