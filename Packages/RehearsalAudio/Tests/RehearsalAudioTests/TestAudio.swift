// TestAudio.swift: writes small generated files (a sine, silence) for the tests that read audio back.

import AVFoundation
import XCTest

enum TestAudio {
  static func tempURL(_ ext: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("rehearsal-\(UUID().uuidString).\(ext)")
  }

  /// A 16-bit WAV of `seconds`, a sine of `amp` and `hz` (amp 0 is silence).
  static func wav(seconds: Double, amp: Float, hz: Double = 220, rate: Double = 8000, channels: Int = 1) throws -> URL {
    let url = tempURL("wav")
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(channels), interleaved: false)!
    let file = try AVAudioFile(forWriting: url, settings: [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
      AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 16,
    ])
    let frames = AVAudioFrameCount(seconds * rate)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
    buf.frameLength = frames
    for c in 0..<channels {
      for i in 0..<Int(frames) { buf.floatChannelData![c][i] = amp * Float(sin(2 * Double.pi * hz * Double(i) / rate)) }
    }
    try file.write(from: buf)
    return url
  }
}
