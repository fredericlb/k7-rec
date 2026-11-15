// TakePlayer.swift: plays a take, with seek, a range that may loop, and the take's playback gain.
// What reads wrong: pause drops the schedule and play re-schedules from the frame it stood on.

import AVFoundation

public enum PlayerState: Sendable, Equatable { case stopped, playing, paused }

@MainActor
public final class TakePlayer: PlaybackYielding {
  public private(set) var state = PlayerState.stopped
  public let durationSec: Double
  public var onFinish: (() -> Void)?
  public var gain: Double { didSet { eq.globalGain = Self.decibels(gain) } }

  private let engine: AVAudioEngine
  private let node = AVAudioPlayerNode()
  private let eq = AVAudioUnitEQ(numberOfBands: 0)
  private let file: AVAudioFile
  private let rate: Double
  private let coordinator: PlaybackCoordinator
  private var rangeStart = 0
  private var rangeEnd = 0
  private var loops = false
  private var anchor = 0
  private var resumeFrame = 0
  private var generation = 0
  // Offline rendering never reports played-back, so a test asks for consumed.
  var completionType = AVAudioPlayerNodeCompletionCallbackType.dataPlayedBack

  public init(
    url: URL, gain: Double = 1, engine: AVAudioEngine = AVAudioEngine(), coordinator: PlaybackCoordinator? = nil
  ) throws {
    file = try AVAudioFile(forReading: url)
    rate = file.processingFormat.sampleRate
    self.engine = engine
    self.coordinator = coordinator ?? .shared
    self.gain = gain
    rangeEnd = Int(file.length)
    durationSec = Double(file.length) / rate
    engine.attach(node)
    engine.attach(eq)
    engine.connect(node, to: eq, format: file.processingFormat)
    engine.connect(eq, to: engine.mainMixerNode, format: file.processingFormat)
    eq.globalGain = Self.decibels(gain)
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
    try AudioSessionConfig.activate()
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

  private var currentFrame: Int {
    guard state == .playing, let t = node.lastRenderTime, let p = node.playerTime(forNodeTime: t) else { return resumeFrame }
    return Playhead.frame(from: anchor, rangeStart: rangeStart, rangeEnd: rangeEnd, loops: loops, played: max(0, Int(p.sampleTime)))
  }

  private func schedule() {
    node.stop()
    generation += 1
    anchor = resumeFrame
    queue(from: resumeFrame)
    if loops { queue(from: rangeStart) }
    node.play()
  }

  private func queue(from start: Int) {
    let count = rangeEnd - start
    guard count > 0 else { return }
    let g = generation
    node.scheduleSegment(file, startingFrame: AVAudioFramePosition(start), frameCount: AVAudioFrameCount(count), at: nil, completionCallbackType: completionType) { [weak self] _ in
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
  }

  private func frame(_ sec: Double) -> Int { Int((max(0, sec) * rate).rounded()) }

  /// The EQ's global gain, capped at the 24 dB it accepts.
  static func decibels(_ gain: Double) -> Float { Float(min(24, max(-96, 20 * log10(max(gain, 1e-6))))) }
}
