// Gain.swift: the peak-based normalisation, applied once at stop (docs/audio.md).
// What reads wrong: the RMS envelope and the audio are levelled from two different peaks.

import Foundation

public enum Gain {
  /// The loudest moment is aimed just under full scale, about -1 dBFS.
  public static let targetPeak = 0.9
  public static let maxGain = 32.0

  /// The factor that brings the loudest RMS sample to the target; the envelope's gain.
  public static func envelope(rawPeak: Double) -> Double {
    rawPeak > 0 ? min(maxGain, targetPeak / rawPeak) : maxGain
  }

  /// The factor that brings the loudest actual sample to the target; the audio's gain, 1 for silence.
  public static func playback(truePeak: Double) -> Double {
    truePeak > 0 ? min(maxGain, targetPeak / truePeak) : 1
  }
}
