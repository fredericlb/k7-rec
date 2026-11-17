// SegmentReader.swift: reads a file as stereo float at the model's rate, a few frames at a time.
// What a reader gets wrong: a read shorter than asked means the end of the file, and the next read is empty.

import AVFoundation

final class SegmentReader: @unchecked Sendable {
  private let file: AVAudioFile
  private let converter: AVAudioConverter
  private let format: AVAudioFormat
  private var inputEnded = false
  /// A file already at the target format is read as is, with no conversion.
  private let direct: Bool
  /// The frames of the file at the target rate, rounded; only for progress.
  let estimatedFrames: Int

  init(url: URL, rate: Double) throws {
    file = try AVAudioFile(forReading: url)
    guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false),
      let converter = AVAudioConverter(from: file.processingFormat, to: target)
    else { throw StemError.unreadable }
    (format, self.converter) = (target, converter)
    direct = file.processingFormat == target
    estimatedFrames = Int((Double(file.length) * rate / file.processingFormat.sampleRate).rounded())
  }

  /// Up to `frames` frames as [channel][frame]; fewer only at the end of the file.
  func read(_ frames: Int) throws -> [[Float]] {
    var out: [[Float]] = [[], []]
    if direct {
      guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return out }
      if file.framePosition < file.length { try file.read(into: buffer, frameCount: AVAudioFrameCount(frames)) }
      let n = Int(buffer.frameLength)
      return (0..<2).map { Array(UnsafeBufferPointer(start: buffer.floatChannelData![$0], count: n)) }
    }
    while out[0].count < frames {
      let want = AVAudioFrameCount(frames - out[0].count)
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: want) else { throw StemError.unreadable }
      var failure: NSError?
      let status = converter.convert(to: buffer, error: &failure) { [self] _, status in
        guard !inputEnded, let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384),
          (try? file.read(into: chunk)) != nil, chunk.frameLength > 0
        else {
          inputEnded = true
          status.pointee = .endOfStream
          return nil
        }
        status.pointee = .haveData
        return chunk
      }
      if status == .error { throw failure ?? StemError.unreadable }
      let n = Int(buffer.frameLength)
      for c in 0..<2 { out[c].append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![c], count: n)) }
      if status == .endOfStream || n == 0 { break }
    }
    return out
  }
}
