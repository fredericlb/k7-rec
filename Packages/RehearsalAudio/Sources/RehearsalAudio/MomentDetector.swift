// MomentDetector.swift: finds a take's moments over its envelope, a port of detect.ts (packages/recorder/docs/recorder.md).
// What reads wrong: the floor is the MINIMUM volume cared about, a moment is whatever is not a long enough silence.

import Foundation

/// Detected moments shorter than this are ignored: a brief blip is not a moment.
public let minMomentSec = 4.0

public struct DetectedMoment: Equatable, Codable, Sendable {
  public var startSec: Double
  public var endSec: Double
  public var durationSec: Double
  public var avg: Double
  public var peak: Double
}

public struct DetectResult: Equatable, Sendable {
  public var floor: Double
  public var silence: Double
  public var peak: Double
  public var moments: [DetectedMoment]
}

public enum MomentDetector {
  /// `floor` defaults to 15% of the envelope's peak; `silence` is the quiet seconds that cut a moment.
  public static func detect(envelope: Envelope, floor: Double? = nil, silence: Double = 2) -> DetectResult {
    let samples = envelope.samples
    guard !samples.isEmpty else { return DetectResult(floor: 0, silence: silence, peak: 0, moments: []) }
    let dt = Double(envelope.intervalMs) / 1000
    let n = samples.count
    let peak = samples.max() ?? 0
    guard peak > 0 else { return DetectResult(floor: 0, silence: silence, peak: 0, moments: []) }

    let threshold = floor ?? peak * 0.15
    let minSilenceSamples = max(1, Int((silence / dt).rounded(.up)))

    var silent = [Bool](repeating: false, count: n)
    var quietStart = -1
    for i in 0...n {
      if i < n && samples[i] < threshold {
        if quietStart == -1 { quietStart = i }
      } else {
        if quietStart != -1 && i - quietStart >= minSilenceSamples {
          for j in quietStart..<i { silent[j] = true }
        }
        quietStart = -1
      }
    }

    var prefix = [Double](repeating: 0, count: n + 1)
    for i in 0..<n { prefix[i + 1] = prefix[i] + samples[i] }

    var moments: [DetectedMoment] = []
    var start = -1
    for i in 0...n {
      if i < n && !silent[i] {
        if start == -1 { start = i }
      } else if start != -1 {
        if let m = moment(start, i, dt, samples, prefix) { moments.append(m) }
        start = -1
      }
    }
    return DetectResult(floor: threshold, silence: silence, peak: peak, moments: moments)
  }

  private static func moment(_ s: Int, _ e: Int, _ dt: Double, _ samples: [Double], _ prefix: [Double]) -> DetectedMoment? {
    if Double(e - s) * dt < minMomentSec { return nil }
    var peak = 0.0
    for i in s..<e { peak = max(peak, samples[i]) }
    let avg = (prefix[e] - prefix[s]) / Double(e - s)
    return DetectedMoment(
      startSec: round2(Double(s) * dt), endSec: round2(Double(e) * dt),
      durationSec: round2(Double(e - s) * dt), avg: round4(avg), peak: round4(peak))
  }
}

func round2(_ v: Double) -> Double { jsRound(v * 100) / 100 }
