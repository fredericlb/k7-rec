// EnvelopeReader.swift: a file's envelope, read offline in chunks so a long take never sits in memory whole.
// What reads wrong: channels are averaged to mono before the RMS, and `peak` is the file's loudest actual sample.

import AVFoundation
import Accelerate

public struct FileEnvelope: Equatable, Sendable {
  public var envelope: Envelope
  /// The loudest absolute sample of the file, 0 for silence.
  public var truePeak: Double
  public var durationSec: Double
}

public enum EnvelopeReader {
  public static func read(url: URL, intervalMs: Int = defaultEnvelopeIntervalMs) throws -> FileEnvelope {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    var builder = EnvelopeBuilder(sampleRate: format.sampleRate, intervalMs: intervalMs)
    let chunk: AVAudioFrameCount = 16_384
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
      throw CocoaError(.fileReadUnknown)
    }
    var mono = [Float](repeating: 0, count: Int(chunk))
    var truePeak: Float = 0
    while file.framePosition < file.length {
      try file.read(into: buffer, frameCount: chunk)
      let n = Int(buffer.frameLength)
      if n == 0 { break }
      guard let data = buffer.floatChannelData else { throw CocoaError(.fileReadUnknown) }
      let channels = Int(format.channelCount)
      mono.withUnsafeMutableBufferPointer { out in
        out.baseAddress!.update(from: data[0], count: n)
        for c in 1..<max(channels, 1) { vDSP_vadd(out.baseAddress!, 1, data[c], 1, out.baseAddress!, 1, vDSP_Length(n)) }
        if channels > 1 {
          var div = Float(channels)
          vDSP_vsdiv(out.baseAddress!, 1, &div, out.baseAddress!, 1, vDSP_Length(n))
        }
        var m: Float = 0
        vDSP_maxmgv(out.baseAddress!, 1, &m, vDSP_Length(n))
        truePeak = max(truePeak, m)
        builder.feed(UnsafeBufferPointer(start: out.baseAddress, count: n))
      }
    }
    let envelope = builder.finish()
    return FileEnvelope(
      envelope: envelope, truePeak: Double(truePeak),
      durationSec: Double(file.length) / format.sampleRate)
  }
}
