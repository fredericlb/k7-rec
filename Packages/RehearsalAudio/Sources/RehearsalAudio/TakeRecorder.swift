// TakeRecorder.swift: records a take, live level and envelope while it runs, one levelled m4a when it stops.
// What reads wrong: the file on disk during a take is the RAW input; the gain is applied once, at stop (docs/audio.md).

import Accelerate
import AVFoundation

public enum RecorderEvent: Sendable, Equatable {
  /// The loudness of the latest chunk, 0...1, for a meter.
  case level(rms: Float, peak: Float)
  /// A closed envelope bucket, raw (ungained), and its index in this take.
  case envelope(index: Int, sample: Double)
  /// The input died or the session was interrupted; the take is paused, `pauseReason` says which.
  case lost
}

public enum RecorderState: Sendable, Equatable { case idle, recording, paused, stopped }

/// Why a paused take is paused; only `.user` is the caller's own doing.
public enum PauseReason: Sendable, Equatable { case user, inputLost, interrupted }

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
  /// The factor already baked into this take's audio (the earlier part is untouched): play the file at 1.
  public var appliedGain: Double
  /// Where the new part starts in the file, 0 for a first take.
  public var offsetSec: Double
  /// The raw input this file was made from; it stays until `confirmSaved()`.
  public var rawURL: URL

  /// Call once the take is saved: the raw input and its sidecar go, the m4a is all that is left.
  public func confirmSaved() {
    try? FileManager.default.removeItem(at: rawURL)
    TakeSidecar.remove(for: rawURL)
  }
}

public enum RecorderError: Error {
  case notRecording, nothingRecorded
  /// The input's rate changed while paused; stop this take and continue it with `start(extending:)`.
  case rateChanged
}

public final class TakeRecorder: @unchecked Sendable {
  public let events: AsyncStream<RecorderEvent>
  private let continuation: AsyncStream<RecorderEvent>.Continuation
  private let input: AudioInput
  private let session: SessionHost
  private let headsetInput: Bool
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
  private var reason: PauseReason?

  /// `headsetInput` lets a Bluetooth headset's microphone be the input, at the price of narrowband sound.
  public init(
    input: AudioInput = EngineInput(), directory: URL, intervalMs: Int = defaultEnvelopeIntervalMs,
    session: SessionHost = SystemSession(), headsetInput: Bool = false
  ) {
    self.input = input
    self.session = session
    self.headsetInput = headsetInput
    self.directory = directory
    self.intervalMs = intervalMs
    (events, continuation) = AsyncStream.makeStream(of: RecorderEvent.self, bufferingPolicy: .bufferingNewest(256))
  }

  deinit {
    continuation.finish()
    input.stop()
    session.unobserve()
  }

  public var status: RecorderState { locked { state } }

  /// Why the take is paused, nil while it is not.
  public var pauseReason: PauseReason? { locked { state == .paused ? reason : nil } }

  /// Recorded seconds so far, pauses excluded, for whoever draws at frame rate.
  public var elapsedSec: Double { locked { Double(frames) / rate } }

  /// The raw input's loudest sample so far, for a preview level.
  public var currentTruePeak: Double { locked { Double(truePeak) } }

  /// Starts a take, or continues `extending` one: the new part is joined to the old at stop.
  public func start(extending: ExistingTake? = nil) throws {
    try locked {
      guard state == .idle else { throw RecorderError.notRecording }
    }
    try session.activate(recording: true, headsetInput: headsetInput)
    let sr = input.sampleRate
    let url = directory.appendingPathComponent("take-\(UUID().uuidString).raw.caf")
    let file = try RawTakeFile(url: url, sampleRate: sr)
    do {
      try TakeSidecar(intervalMs: intervalMs, existing: extending).write(for: url)
      locked {
        rate = sr
        raw = file
        existing = extending
        builder = EnvelopeBuilder(sampleRate: sr, intervalMs: intervalMs)
        state = .recording
        reason = nil
      }
      input.onLost = { [weak self] in self?.lose(.inputLost) }
      session.onInterruption = { [weak self] in self?.interrupted($0) }
      session.observe()
      try input.start { [weak self] in self?.ingest($0) }
    } catch {
      input.stop()
      session.unobserve()
      try? file.close()
      try? FileManager.default.removeItem(at: url)
      TakeSidecar.remove(for: url)
      locked {
        raw = nil
        builder = nil
        state = .idle
      }
      throw error
    }
  }

  public func pause() { _ = pause(.user) }

  @discardableResult
  private func pause(_ why: PauseReason) -> Bool {
    let was = locked { () -> Bool in
      guard state == .recording else { return false }
      state = .paused
      reason = why
      return true
    }
    if was { input.stop() }
    return was
  }

  /// Continues a paused take, whatever paused it: the session is activated again first.
  public func resume() throws {
    try locked { guard state == .paused else { throw RecorderError.notRecording } }
    try session.activate(recording: true, headsetInput: headsetInput)
    try input.start { [weak self] in self?.ingest($0) }
    guard input.sampleRate == locked({ rate }) else {
      input.stop()
      throw RecorderError.rateChanged
    }
    locked {
      state = .recording
      reason = nil
    }
  }

  /// Stops, levels the raw take at the peak, and writes the m4a; the raw file stays until `confirmSaved()`.
  public func stop() async throws -> TakeResult {
    let snap = try locked { () -> (RawTakeFile, EnvelopeBuilder, ExistingTake?, Float, Int, Double) in
      guard state == .recording || state == .paused, let raw, let builder else { throw RecorderError.notRecording }
      state = .stopped
      return (raw, builder, existing, truePeak, frames, rate)
    }
    input.stop()
    session.unobserve()
    continuation.finish()
    try snap.0.close()
    var b = snap.1
    let newEnvelope = b.finish()
    guard snap.4 > 0 else {
      try? FileManager.default.removeItem(at: snap.0.url)
      TakeSidecar.remove(for: snap.0.url)
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
    session.unobserve()
    continuation.finish()
    let r = locked { () -> RawTakeFile? in
      state = .stopped
      return raw
    }
    try? r?.close()
    if let u = r?.url {
      try? FileManager.default.removeItem(at: u)
      TakeSidecar.remove(for: u)
    }
  }

  /// Raw takes a crash left in `directory`, to be finished with `recover(raw:)` or deleted.
  public static func leftovers(in directory: URL) -> [URL] {
    let all = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    return all.filter { $0.lastPathComponent.hasSuffix(".raw.caf") }
  }

  /// Turns a raw take a crash left into a levelled m4a beside it, as `stop` would; `confirmSaved()` frees the raw file.
  public static func recover(raw: URL) async throws -> TakeResult {
    let side = TakeSidecar.read(for: raw)
    let out = raw.deletingLastPathComponent().appendingPathComponent("take-\(UUID().uuidString).m4a")
    return try await Task.detached {
      let file = try AVAudioFile(forReading: raw)
      guard file.length > 0 else {
        // A continuation that crashed before any frame: the earlier part is the take.
        if let earlier = side?.existing(besides: raw) {
          return TakeResult(
            url: earlier.url, durationSec: AVAudioFile.lengthSec(earlier.url), envelope: earlier.envelope,
            appliedGain: 1, offsetSec: 0, rawURL: raw)
        }
        try? FileManager.default.removeItem(at: raw)
        TakeSidecar.remove(for: raw)
        throw RecorderError.nothingRecorded
      }
      let read = try EnvelopeReader.read(url: raw, intervalMs: side?.intervalMs ?? defaultEnvelopeIntervalMs)
      return try finish(
        raw: raw, to: out, existing: side?.existing(besides: raw), envelope: read.envelope,
        truePeak: Float(read.truePeak), frames: Int(file.length), rate: file.processingFormat.sampleRate)
    }.value
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
    do { try TakeEncoder.write(parts: parts, to: out, sampleRate: rate) } catch {
      try? FileManager.default.removeItem(at: out)
      throw error
    }
    let levelled = envelope.scaled(by: Gain.envelope(rawPeak: envelope.peak))
    let offset = existing.map { Double(AVAudioFile.lengthSec($0.url)) } ?? 0
    return TakeResult(
      url: out, durationSec: offset + Double(frames) / rate,
      envelope: Envelope(intervalMs: envelope.intervalMs, samples: base.samples + levelled.samples),
      appliedGain: gain, offsetSec: offset, rawURL: raw)
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

  private func lose(_ why: PauseReason) {
    if pause(why) { continuation.yield(.lost) }
  }

  private func interrupted(_ event: InterruptionEvent) {
    switch event {
    case .began, .mediaServicesReset: lose(.interrupted)
    case .ended: break  // only an explicit resume() continues the take
    }
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
