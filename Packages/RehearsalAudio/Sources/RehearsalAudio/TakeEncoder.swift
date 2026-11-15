// TakeEncoder.swift: the raw take and an earlier file, levelled and written once as one AAC m4a (docs/audio.md).
// What reads wrong: an earlier file is decoded and joined, never byte-appended; AAC does not concatenate.

import AVFoundation
import Accelerate

public enum TakeEncoder {
  public struct Part: Sendable {
    public var url: URL
    public var gain: Float
    public init(url: URL, gain: Float) {
      self.url = url
      self.gain = gain
    }
  }

  /// A low input rate (a Bluetooth headset's 16 kHz) gets a bit rate the encoder accepts.
  /// Writes `parts`, in order, each at its own gain, as one mono AAC file at `sampleRate`.
  public static func write(parts: [Part], to url: URL, sampleRate: Double, bitRate: Int = 128_000) throws {
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: sampleRate >= 32_000 ? bitRate : 24_000,
    ]
    let out = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    for part in parts { try copy(part, into: out) }
  }

  private static func copy(_ part: Part, into out: AVAudioFile) throws {
    let file = try AVAudioFile(forReading: part.url)
    let src = file.processingFormat
    let dst = out.processingFormat
    let chunk: AVAudioFrameCount = 16_384
    guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: chunk) else { throw CocoaError(.fileWriteUnknown) }
    let converter = src == dst ? nil : AVAudioConverter(from: src, to: dst)
    if converter == nil && src != dst { throw CocoaError(.fileWriteUnknown) }
    while file.framePosition < file.length {
      try file.read(into: inBuf, frameCount: chunk)
      if inBuf.frameLength == 0 { break }
      let ready = try converted(inBuf, converter, dst)
      if let data = ready.floatChannelData, part.gain != 1 {
        var g = part.gain
        for c in 0..<Int(dst.channelCount) { vDSP_vsmul(data[c], 1, &g, data[c], 1, vDSP_Length(ready.frameLength)) }
      }
      try out.write(from: ready)
    }
  }

  private static func converted(_ buf: AVAudioPCMBuffer, _ converter: AVAudioConverter?, _ dst: AVAudioFormat) throws -> AVAudioPCMBuffer {
    guard let converter else { return buf }
    let ratio = dst.sampleRate / buf.format.sampleRate
    let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 64
    guard let out = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: cap) else { throw CocoaError(.fileWriteUnknown) }
    var fed = false
    var err: NSError?
    converter.convert(to: out, error: &err) { _, status in
      if fed {
        status.pointee = .noDataNow
        return nil
      }
      fed = true
      status.pointee = .haveData
      return buf
    }
    if let err { throw err }
    return out
  }
}
