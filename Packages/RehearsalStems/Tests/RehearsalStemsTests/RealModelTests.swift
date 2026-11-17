// RealModelTests.swift: runs the real Core ML model when STEM_MODEL names a .mlpackage; skipped otherwise.

import AVFoundation
import XCTest
@testable import RehearsalStems

final class RealModelTests: XCTestCase {
  func testTheRealModelSplitsASegmentAndTheStemsAddUpToTheInput() async throws {
    guard let path = ProcessInfo.processInfo.environment["STEM_MODEL"] else { throw XCTSkip("STEM_MODEL is not set") }
    let compiled = try await CoreMLSegmentModel.compile(URL(fileURLWithPath: path))
    let model = try CoreMLSegmentModel(url: compiled)
    XCTAssertEqual(model.segmentFrames, 343_980)
    let n = model.segmentFrames
    let mix = (0..<2).map { c in (0..<n).map { i in 0.3 * Float(sin(2 * Double.pi * (220 + 110 * Double(c)) * Double(i) / 44_100)) } }
    let stems = try model.separate(mix)
    XCTAssertEqual(stems.count, 4)
    var worst: Float = 0
    for c in 0..<2 {
      for i in stride(from: 20_000, to: n - 20_000, by: 97) {
        worst = max(worst, abs(stems.reduce(0) { $0 + $1[c][i] } - mix[c][i]))
      }
    }
    XCTAssertLessThan(worst, 0.1, "the four stems of a mix sum back to it")
  }

  func testTheRealModelSeparatesAFileEndToEnd() async throws {
    guard let path = ProcessInfo.processInfo.environment["STEM_MODEL"] else { throw XCTSkip("STEM_MODEL is not set") }
    let model = try CoreMLSegmentModel(url: try await CoreMLSegmentModel.compile(URL(fileURLWithPath: path)))
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("real-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let src = dir.appendingPathComponent("src.wav")
    let seconds = Double(ProcessInfo.processInfo.environment["STEM_SECONDS"] ?? "12") ?? 12
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)!
    do {
    let file = try AVAudioFile(forWriting: src, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16])
    let frames = AVAudioFrameCount(seconds * 44_100)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
    buf.frameLength = frames
    for c in 0..<2 { for i in 0..<Int(frames) { buf.floatChannelData![c][i] = 0.3 * Float(sin(2 * Double.pi * 220 * Double(i) / 44_100)) } }
    try file.write(from: buf)
    }
    try await StemSeparator(model: model).separate(source: src, into: dir.appendingPathComponent("stems"))
    let found = try XCTUnwrap(Stem.existing(in: dir))
    let length = try AVAudioFile(forReading: found[.vocals]!).length
    XCTAssertEqual(Double(length), seconds * 44_100, accuracy: 3000)
  }
}
