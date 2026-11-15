// Envelope.swift: a take's loudness as RMS buckets of a fixed interval, as liveEnvelope.ts and the TS Envelope carry it.
// What reads wrong: a bucket is a window of raw frames, and its gain is applied later, never while recording.

import Foundation

public let defaultEnvelopeIntervalMs = 200

public struct Envelope: Equatable, Codable, Sendable {
  public var intervalMs: Int
  public var samples: [Double]

  public init(intervalMs: Int = defaultEnvelopeIntervalMs, samples: [Double] = []) {
    self.intervalMs = intervalMs
    self.samples = samples
  }

  public var durationSec: Double { Double(samples.count) * Double(intervalMs) / 1000 }

  /// The loudest sample, 0 when empty.
  public var peak: Double { samples.max() ?? 0 }

  /// Every sample times `factor`, capped at 1 and rounded to four places, as a stop stores it.
  public func scaled(by factor: Double) -> Envelope {
    Envelope(intervalMs: intervalMs, samples: samples.map { round4(min(1, $0 * factor)) })
  }
}

/// Turns a stream of mono frames into RMS buckets of `intervalMs`, whatever the size of the chunks fed.
public struct EnvelopeBuilder: Sendable {
  public let intervalMs: Int
  public let sampleRate: Double
  public private(set) var samples: [Double] = []
  private var sumSquares = 0.0
  private var filled = 0
  private let bucketFrames: Int

  public init(sampleRate: Double, intervalMs: Int = defaultEnvelopeIntervalMs) {
    self.intervalMs = intervalMs
    self.sampleRate = sampleRate
    bucketFrames = max(1, Int((sampleRate * Double(intervalMs) / 1000).rounded()))
  }

  public mutating func feed(_ frames: UnsafeBufferPointer<Float>) {
    for v in frames {
      sumSquares += Double(v) * Double(v)
      filled += 1
      if filled == bucketFrames { closeBucket() }
    }
  }

  public mutating func feed(_ frames: [Float]) {
    frames.withUnsafeBufferPointer { feed($0) }
  }

  /// Buckets closed so far; a partial last bucket is kept out until `finish`.
  public var envelope: Envelope { Envelope(intervalMs: intervalMs, samples: samples) }

  /// Closes the partial bucket, if any, so a take's tail is not lost.
  public mutating func finish() -> Envelope {
    if filled > 0 { closeBucket() }
    return envelope
  }

  private mutating func closeBucket() {
    samples.append(round4(sqrt(sumSquares / Double(filled))))
    sumSquares = 0
    filled = 0
  }
}

/// The take as it is drawn: a resumed take's saved samples, then the new ones at the live gain.
public struct LiveEnvelope: Sendable {
  public private(set) var envelope: Envelope
  /// Where the new take starts on the drawn timeline, in seconds.
  public let offsetSec: Double
  /// The loudest drawn sample of the new take, 0 before any.
  public private(set) var peak = 0.0
  private var pulled = 0

  public init(base: [Double], intervalMs: Int = defaultEnvelopeIntervalMs) {
    envelope = Envelope(intervalMs: intervalMs, samples: base)
    offsetSec = Double(base.count * intervalMs) / 1000
  }

  /// Draws the raw samples not yet drawn, at `gain`.
  public mutating func pull(raw: [Double], gain: Double) {
    while pulled < raw.count {
      let v = min(1, raw[pulled] * gain)
      envelope.samples.append(v)
      if v > peak { peak = v }
      pulled += 1
    }
  }
}

@inline(__always) func round4(_ v: Double) -> Double { jsRound(v * 10_000) / 10_000 }

/// Math.round: halves go up, which matters for the digits the TS stored.
@inline(__always) func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }
