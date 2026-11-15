// TakeRecorder.swift: records a take, live level and envelope while it runs, one levelled m4a when it stops.
// What reads wrong: the file on disk during a take is the RAW input; the gain is applied once, at stop (docs/audio.md).

import Accelerate
import AVFoundation

public enum RecorderEvent: Sendable, Equatable {
  /// The loudness of the latest chunk, 0...1, for a meter.
  case level(rms: Float, peak: Float)
  /// A closed envelope bucket, raw (ungained), and its index in this take.
  case envelope(index: Int, sample: Double)
  /// The input died; the take is paused with what came before kept.
  case lost
}

public enum RecorderState: Sendable, Equatable { case idle, recording, paused, stopped }

/// An earlier take being continued: its audio file and its envelope as saved.
public struct ExistingTake: Sendable {
  public var url: URL
  public var envelope: Envelope
  public init(url: URL, envelope: Envelope) {
    self.url = url
    self.envelope = envelope
  }
}

public struct TakeResult: Sendable, Equatable {
  public var url: URL
  /// The whole file's length, the earlier take included.
  public var durationSec: Double
  /// The earlier envelope then the new samples, the new ones levelled.
  public var envelope: Envelope
  /// The factor baked into this take's audio (the earlier part is untouched).
  public var gain: Double
  /// Where the new part starts in the file, 0 for a first take.
  public var offsetSec: Double
}

public enum RecorderError: Error { case notRecording, nothingRecorded }

public final class TakeRecorder: @unchecked Sendable {
  public let events: AsyncStream<RecorderEvent>
  private let continuation: AsyncStream<RecorderEvent>.Continuation
  private let input: AudioInput
  private let directory: URL
  private let intervalMs: Int
  private let lock = NSLock()
  private var state = RecorderState.idle
  private var builder: EnvelopeBuilder?
  private var raw: RawTakeFile?
  private var existing: ExistingTake?
  private var frames = 0
  private var emitted = 0
  private var truePeak: Float = 0
  private var rate = 44_100.0

  public init(input: AudioInput = EngineInput(), directory: URL, intervalMs: Int = defaultEnvelopeIntervalMs) {
    self.input = input
    self.directory = directory
    self.intervalMs = intervalMs
    (events, continuation) = AsyncStream.makeStream(of: RecorderEvent.self, bufferingPolicy: .bufferingNewest(256))
  }

  public var status: RecorderState { locked { state } }

  /// Recorded seconds so far, pauses excluded, for whoever draws at frame rate.
  public var elapsedSec: Double { locked { Double(frames) / rate } }

  /// The raw input's loudest sample so far, for a preview level.
  public var currentTruePeak: Double { locked { Double(truePeak) } }

  /// Starts a take, or continues `extending` one: the new part is joined to the old at stop.
  public func start(extending: ExistingTake? = nil) throws {
    try locked {
      guard state == .idle else { throw RecorderError.notRecording }
    }
    try AudioSessionConfig.activate()
    input.onLost = { [weak self] in self?.lose() }
    try input.start { [weak self] in self?.ingest($0) }
    let sr = input.sampleRate
    let file = try RawTakeFile(url: directory.appendingPathComponent("take-\(UUID().uuidString).raw.caf"), sampleRate: sr)
    locked {
      rate = sr
      raw = file
      existing = extending
      builder = EnvelopeBuilder(sampleRate: sr, intervalMs: intervalMs)
      state = .recording
    }
  }

  public func pause() {
    let was = locked { () -> Bool in
      guard state == .recording else { return false }
      state = .paused
      return true
    }
    if was { input.stop() }
  }

  public func resume() throws {
    try locked { guard state == .paused else { throw RecorderError.notRecording } }
    try input.start { [weak self] in self?.ingest($0) }
    locked { state = .recording }
  }

  /// Stops, levels the raw take at the peak, and writes the m4a; the raw file goes once it is written.
  public func stop() async throws -> TakeResult {
    let snap = try locked { () -> (RawTakeFile, EnvelopeBuilder, ExistingTake?, Float, Int, Double) in
      guard state == .recording || state == .paused, let raw, let builder else { throw RecorderError.notRecording }
      state = .stopped
      return (raw, builder, existing, truePeak, frames, rate)
    }
    input.stop()
    continuation.finish()
    try snap.0.close()
    var b = snap.1
    let newEnvelope = b.finish()
    guard snap.4 > 0 else {
      try? FileManager.default.removeItem(at: snap.0.url)
      throw RecorderError.nothingRecorded
    }
    let out = directory.appendingPathComponent("take-\(UUID().uuidString).m4a")
    return try await Task.detached {
      try Self.finish(raw: snap.0.url, to: out, existing: snap.2, envelope: newEnvelope, truePeak: snap.3, frames: snap.4, rate: snap.5)
    }.value
  }

  /// Drops the take: the input closes and the raw file goes.
  public func discard() {
    input.stop()
    continuation.finish()
    let r = locked { () -> RawTakeFile? in
      state = .stopped
      return raw
    }
    try? r?.close()
    if let u = r?.url { try? FileManager.default.removeItem(at: u) }
  }

  /// Raw takes a crash left in `directory`, to be finished with `finish(raw:...)` or deleted.
  public static func leftovers(in directory: URL) -> [URL] {
    let all = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    return all.filter { $0.lastPathComponent.hasSuffix(".raw.caf") }
  }

  static func finish(
    raw: URL, to out: URL, existing: ExistingTake?, envelope: Envelope, truePeak: Float, frames: Int, rate: Double
  ) throws -> TakeResult {
    let gain = Gain.playback(truePeak: Double(truePeak))
    var parts: [TakeEncoder.Part] = []
    var base = Envelope(intervalMs: envelope.intervalMs)
    if let existing {
      parts.append(.init(url: existing.url, gain: 1))
      base = existing.envelope
    }
    parts.append(.init(url: raw, gain: Float(gain)))
    try TakeEncoder.write(parts: parts, to: out, sampleRate: rate)
    try? FileManager.default.removeItem(at: raw)
    let levelled = envelope.scaled(by: Gain.envelope(rawPeak: envelope.peak))
    let offset = existing.map { Double(AVAudioFile.lengthSec($0.url)) } ?? 0
    return TakeResult(
      url: out, durationSec: offset + Double(frames) / rate,
      envelope: Envelope(intervalMs: envelope.intervalMs, samples: base.samples + levelled.samples),
      gain: gain, offsetSec: offset)
  }

  private func ingest(_ chunk: UnsafeBufferPointer<Float>) {
    guard chunk.count > 0 else { return }
    var rms: Float = 0
    var peak: Float = 0
    vDSP_rmsqv(chunk.baseAddress!, 1, &rms, vDSP_Length(chunk.count))
    vDSP_maxmgv(chunk.baseAddress!, 1, &peak, vDSP_Length(chunk.count))
    var closed: [Double] = []
    var base = 0
    let file: RawTakeFile? = locked {
      guard state == .recording, builder != nil else { return nil }
      builder!.feed(chunk)
      frames += chunk.count
      if peak > truePeak { truePeak = peak }
      base = emitted
      closed = Array(builder!.samples[emitted...])
      emitted = builder!.samples.count
      return raw
    }
    guard let file else { return }
    file.append(chunk)
    continuation.yield(.level(rms: rms, peak: peak))
    for (i, s) in closed.enumerated() { continuation.yield(.envelope(index: base + i, sample: s)) }
  }

  private func lose() {
    pause()
    continuation.yield(.lost)
  }

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}

extension AVAudioFile {
  static func lengthSec(_ url: URL) -> Double {
    guard let f = try? AVAudioFile(forReading: url) else { return 0 }
    return Double(f.length) / f.processingFormat.sampleRate
  }
}
