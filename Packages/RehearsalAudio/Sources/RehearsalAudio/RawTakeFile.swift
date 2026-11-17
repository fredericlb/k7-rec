// RawTakeFile.swift: the take's raw input on disk as 32-bit float CAF, written off the audio thread.
// What reads wrong: it is the file a crash leaves behind, so it is never levelled and never deleted early.

import AVFoundation

final class RawTakeFile: @unchecked Sendable {
  let url: URL
  private let queue = DispatchQueue(label: "rehearsal.raw-take")
  private var file: AVAudioFile?
  private let format: AVAudioFormat
  private var failure: Error?

  init(url: URL, sampleRate: Double) throws {
    self.url = url
    format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    file = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
      ], commonFormat: .pcmFormatFloat32, interleaved: false)
  }

  func append(_ frames: UnsafeBufferPointer<Float>) {
    let copy = Array(frames)
    queue.async { [self] in
      guard let file, failure == nil,
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(copy.count))
      else { return }
      buf.frameLength = AVAudioFrameCount(copy.count)
      copy.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: copy.count) }
      do { try file.write(from: buf) } catch { failure = error }
    }
  }

  /// Waits for the queued writes, so the file read now holds everything heard so far.
  func flush() { queue.sync {} }

  /// Waits for the queued writes and closes the file; throws the first write error.
  func close() throws {
    try queue.sync {
      file = nil
      if let failure { throw failure }
    }
  }
}
