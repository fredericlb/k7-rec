// InstrumentalMix.swift: the song without its voice, drums + bass + other summed into one file.
// What a reader gets wrong: it is built from the AAC stems, so it is a second encode, made once and kept beside them.

import AVFoundation

public enum InstrumentalMix {
  /// The file a song folder keeps its instrumental in; it goes with the stems when they are replaced.
  public static let fileName = "instrumental.m4a"

  public static func url(in song: URL) -> URL { Stem.folder(in: song).appendingPathComponent(fileName) }

  /// Sums the stems but the vocals into `url`, a chunk at a time; a failure leaves no file.
  public static func write(from stems: [Stem: URL], to url: URL) throws {
    let parts = try Stem.allCases.filter { $0 != .vocals }.map { stem -> AVAudioFile in
      guard let file = stems[stem] else { throw StemError.unreadable }
      return try AVAudioFile(forReading: file)
    }
    let format = parts[0].processingFormat
    guard parts.allSatisfy({ $0.processingFormat.sampleRate == format.sampleRate && $0.processingFormat.channelCount == 2 }) else { throw StemError.unreadable }
    let work = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)-\(fileName)")
    do {
      var out: StemWriter? = try StemWriter(url: work, rate: format.sampleRate)
      let chunk: AVAudioFrameCount = 32_768
      while true {
        var mix: [[Float]] = [[], []]
        for file in parts where file.framePosition < file.length {
          guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { throw StemError.unreadable }
          try file.read(into: buffer, frameCount: chunk)
          let n = Int(buffer.frameLength)
          for c in 0..<2 {
            let samples = UnsafeBufferPointer(start: buffer.floatChannelData![c], count: n)
            if mix[c].count < n { mix[c] += [Float](repeating: 0, count: n - mix[c].count) }
            for i in 0..<n { mix[c][i] += samples[i] }
          }
        }
        let frames = mix[0].count
        if frames == 0 { break }
        try out?.write(mix.map { $0.map { min(1, max(-1, $0)) } })
      }
      out = nil
      try? FileManager.default.removeItem(at: url)
      try FileManager.default.moveItem(at: work, to: url)
    } catch {
      try? FileManager.default.removeItem(at: work)
      throw error
    }
  }
}
