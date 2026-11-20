// TakePlayer.swift: plays a take, with seek, a range that may loop, and the take's playback gain.
// What reads wrong: pause drops the schedule and play re-schedules from the frame it stood on.

import AVFoundation
import os

public enum PlayerState: Sendable, Equatable { case stopped, playing, paused }

@MainActor
public final class TakePlayer: PlaybackYielding {
  public private(set) var state = PlayerState.stopped
  public let durationSec: Double
  public var onFinish: (() -> Void)?
  /// Called whenever the player pauses, whoever asked: the caller, another player taking the floor, an interruption.
  public var onPause: (() -> Void)?
  public var gain: Double { didSet { applyGain() } }

  private let engine: AVAudioEngine
  private let node = AVAudioPlayerNode()
  private let eq = AVAudioUnitEQ(numberOfBands: 0)
  private let boost = AVAudioUnitEQ(numberOfBands: 0)
  private let file: AVAudioFile
  private let rate: Double
  private let coordinator: PlaybackCoordinator
  private var rangeStart = 0
  private var rangeEnd = 0
  private var loops = false
  private var anchor = 0
  private var resumeFrame = 0
  private var generation = 0
  private var lastFrame = 0
  private let session: SessionHost
  private let configToken = ObserverToken()
  /// The RMS of the last buffer heard, after the gain, written by the audio thread's tap.
  private let meter = OSAllocatedUnfairLock(initialState: Float(0))
  // Offline rendering never reports played-back, so a test asks for consumed.
  var completionType = AVAudioPlayerNodeCompletionCallbackType.dataPlayedBack

  public init(
    url: URL, gain: Double = 1, engine: AVAudioEngine = AVAudioEngine(), coordinator: PlaybackCoordinator? = nil,
    session: SessionHost = SystemSession()
  ) throws {
    self.session = session
    file = try AVAudioFile(forReading: url)
    rate = file.processingFormat.sampleRate
    self.engine = engine
    self.coordinator = coordinator ?? .shared
    self.gain = gain
    rangeEnd = Int(file.length)
    durationSec = Double(file.length) / rate
    engine.attach(node)
    engine.attach(eq)
    engine.attach(boost)
    engine.connect(node, to: eq, format: file.processingFormat)
    engine.connect(eq, to: boost, format: file.processingFormat)
    engine.connect(boost, to: engine.mainMixerNode, format: file.processingFormat)
    applyGain()
    boost.installTap(onBus: 0, bufferSize: 2048, format: nil, block: Self.metering(into: meter))
    session.onInterruption = { [weak self] _ in MainActor.assumeIsolated { self?.pause() } }
    session.observe()
    configToken.set(
      NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) {
        [weak self] _ in MainActor.assumeIsolated { self?.configurationChanged() }
      })
  }

  deinit {
    session.unobserve()
  }

  /// What is heard now, as the RMS of the last buffer after the gain; 0 unless playing.
  public var outputRMS: Float { state == .playing ? meter.withLock { $0 } : 0 }

  /// The tap that keeps the meter; made outside the main actor, since the audio thread calls it.
  nonisolated private static func metering(into meter: OSAllocatedUnfairLock<Float>) -> AVAudioNodeTapBlock {
    { buffer, _ in
      let value = rms(buffer)
      meter.withLock { $0 = value }
    }
  }

  /// The RMS over every channel of a buffer.
  nonisolated static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
    let n = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
    var sum: Float = 0
    for c in 0..<channels { for i in 0..<n { sum += data[c][i] * data[c][i] } }
    return (sum / Float(n * channels)).squareRoot()
  }

  /// The playhead, in seconds from the start of the file.
  public var positionSec: Double { Double(currentFrame) / rate }

  /// Plays only `range` (seconds), looping it or stopping at its end; nil plays the whole file.
  public func setRange(_ range: ClosedRange<Double>?, loops: Bool = false) {
    let wasPlaying = state == .playing
    let from = wasPlaying ? currentFrame : resumeFrame
    rangeStart = range.map { frame($0.lowerBound) } ?? 0
    rangeEnd = range.map { frame($0.upperBound) } ?? Int(file.length)
    self.loops = loops && range != nil
    resumeFrame = min(max(from, rangeStart), rangeEnd)
    if wasPlaying { schedule() }
  }

  public func play() throws {
    guard state != .playing else { return }
    coordinator.claim(self)
    try session.activate(recording: false, headsetInput: false)
    if resumeFrame >= rangeEnd { resumeFrame = rangeStart }
    if !engine.isRunning { try engine.start() }
    schedule()
    state = .playing
  }

  public func pause() {
    guard state == .playing else { return }
    resumeFrame = currentFrame
    halt()
    state = .paused
    onPause?()
  }

  public func stop() {
    halt()
    resumeFrame = rangeStart
    state = .stopped
    coordinator.release(self)
  }

  public func seek(to sec: Double) {
    resumeFrame = min(max(frame(sec), rangeStart), rangeEnd)
    if state == .playing { schedule() }
  }

  public func yieldPlayback() { pause() }

  /// The engine's output changed. On the phone that is a route change (headphones out), and the song pauses; the Mac
  /// reports one as the engine starts, so there the song goes on from where it stood (docs/mac.md).
  private func configurationChanged() {
    #if targetEnvironment(macCatalyst)
    guard state == .playing else { return }
    resumeFrame = currentFrame
    do {
      if !engine.isRunning { try engine.start() }
      schedule()
    } catch { pause() }
    #else
    pause()
    #endif
  }

  private var currentFrame: Int {
    guard state == .playing else { return resumeFrame }
    // A stopped engine has no render time: the last position seen stands, so a pause keeps it.
    guard let t = node.lastRenderTime, let p = node.playerTime(forNodeTime: t) else { return lastFrame }
    lastFrame = Playhead.frame(from: anchor, rangeStart: rangeStart, rangeEnd: rangeEnd, loops: loops, played: max(0, Int(p.sampleTime)))
    return lastFrame
  }

  private func schedule() {
    node.stop()
    generation += 1
    anchor = resumeFrame
    lastFrame = resumeFrame
    queue(from: resumeFrame)
    if loops { queue(from: rangeStart) }
    node.play()
  }

  private func queue(from start: Int) {
    let count = rangeEnd - start
    guard count > 0 else { return }
    let g = generation
    node.scheduleSegment(file, startingFrame: AVAudioFramePosition(start), frameCount: AVAudioFrameCount(count), at: nil, completionCallbackType: completionType) { @Sendable [weak self] _ in
      Task { @MainActor in self?.segmentDone(g) }
    }
  }

  private func segmentDone(_ g: Int) {
    guard g == generation, state == .playing else { return }
    if loops { queue(from: rangeStart) } else { finish() }
  }

  private func finish() {
    halt()
    resumeFrame = rangeEnd
    state = .stopped
    coordinator.release(self)
    onFinish?()
  }

  private func halt() {
    generation += 1
    node.stop()
    engine.pause()
  }

  private func frame(_ sec: Double) -> Int { Int((max(0, sec) * rate).rounded()) }

  private func applyGain() {
    let (first, second) = Self.decibels(gain)
    eq.globalGain = first
    boost.globalGain = second
  }

  /// The decibels for two EQs in series, each accepting up to +24 dB: the first takes the cut and the first 24.
  static func decibels(_ gain: Double) -> (Float, Float) {
    let db = 20 * log10(max(gain, 1e-6))
    return (Float(min(24, max(-96, db))), Float(min(24, max(0, db - 24))))
  }
}
