// StemSeparator.swift: splits a file into the four stems, one segment at a time, writing as it goes.
// What a reader gets wrong: segments overlap and cross-fade, and only the overlap is held, so memory is
// one segment however long the song is. The stems go to a sibling folder that replaces the old set whole.

import AVFoundation

public struct StemSeparator: Sendable {
  private let model: SegmentModel
  private let overlap: Int

  public init(model: SegmentModel, overlapSeconds: Double = 1) {
    self.model = model
    overlap = min(max(1, Int(overlapSeconds * model.sampleRate)), model.segmentFrames / 2)
  }

  /// Writes `drums.m4a` ... into `folder`, replacing it on success; a failure or a cancel leaves it untouched.
  public func separate(source: URL, into folder: URL, progress: @Sendable (Double) -> Void = { _ in }) async throws {
    let fm = FileManager.default
    let work = folder.deletingLastPathComponent().appendingPathComponent(".stems-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: work, withIntermediateDirectories: true)
    do {
      try run(source: source, into: work, progress: progress)
      try Task.checkCancellation()
      // The instrumental is made with the set, so a set is never found without it.
      let written = Dictionary(uniqueKeysWithValues: Stem.allCases.map { ($0, work.appendingPathComponent($0.fileName)) })
      try InstrumentalMix.write(from: written, to: work.appendingPathComponent(InstrumentalMix.fileName))
      try Task.checkCancellation()
      progress(1)
      if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
      try fm.moveItem(at: work, to: folder)
    } catch {
      try? fm.removeItem(at: work)
      throw error
    }
  }

  private func run(source: URL, into work: URL, progress: @Sendable (Double) -> Void) throws {
    let reader = try SegmentReader(url: source, rate: model.sampleRate)
    let (length, hop) = (model.segmentFrames, model.segmentFrames - overlap)
    var writers = try Stem.allCases.map { try StemWriter(url: work.appendingPathComponent($0.fileName), rate: model.sampleRate) }
    let head = try reader.read(length)
    guard head[0].count > 0 else { throw StemError.unreadable }
    var valid = head[0].count
    var window = head.map { $0 + [Float](repeating: 0, count: length - valid) }
    var tail: [[[Float]]]?
    var written = 0
    var more = true
    while more {
      try Task.checkCancellation()
      // A pool per segment: Core ML and AVFoundation autorelease their buffers, and a long loop never drains.
      try autoreleasepool {
        let out = try model.separate(window)
        guard out.count == Stem.allCases.count else { throw StemError.wrongStemCount(out.count) }
        let next = try reader.read(hop)
        more = next[0].count > 0
        var from = 0
        if let held = tail {
          for s in 0..<out.count { try writers[s].write(Self.crossfade(held: held[s], head: out[s], overlap: overlap)) }
          from = overlap
        }
        let to = more ? length - overlap : valid
        if to > from { for s in 0..<out.count { try writers[s].write(out[s].map { Array($0[from..<to]) }) } }
        written += max(0, to - from) + (tail == nil ? 0 : overlap)
        progress(min(0.99, Double(written) / Double(max(1, reader.estimatedFrames))))
        guard more else { return }
        tail = out.map { $0.map { Array($0[(length - overlap)..<length]) } }
        let n = next[0].count
        for c in 0..<2 { window[c] = Array(window[c][(length - overlap)..<length]) + next[c] + [Float](repeating: 0, count: hop - n) }
        valid = overlap + n
      }
    }
    writers.removeAll()
  }

  /// `held` fades out as `head`'s first `overlap` frames fade in; the two sum to one signal.
  static func crossfade(held: [[Float]], head: [[Float]], overlap: Int) -> [[Float]] {
    (0..<2).map { c in
      (0..<overlap).map { i in
        let t = Float(i) / Float(overlap)
        return held[c][i] * (1 - t) + head[c][i] * t
      }
    }
  }

}

/// One stem's AAC file, written in the order the frames come.
final class StemWriter {
  private let file: AVAudioFile
  private let format: AVAudioFormat

  init(url: URL, rate: Double) throws {
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false) else { throw StemError.unreadable }
    self.format = format
    var settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2]
    // A low rate refuses a high bit rate, and only a test model runs there.
    if rate >= 32_000 { settings[AVEncoderBitRateKey] = 192_000 }
    file = try AVAudioFile(forWriting: url, settings: settings)
  }

  func write(_ audio: [[Float]]) throws {
    let n = audio[0].count
    guard n > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { return }
    buffer.frameLength = AVAudioFrameCount(n)
    for c in 0..<2 { audio[c].withUnsafeBufferPointer { buffer.floatChannelData![c].update(from: $0.baseAddress!, count: n) } }
    try file.write(from: buffer)
  }
}
