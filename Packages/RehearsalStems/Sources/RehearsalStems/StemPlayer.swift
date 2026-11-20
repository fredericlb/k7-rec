// StemPlayer.swift: plays the four stems together, each with its own gain, from one shared start, pitch-shifted as one.
// What a reader gets wrong: every node starts at the same host time, so the stems stay in step; a seek or a
// mix change while playing re-schedules from the frame the playhead stands on.

import AVFoundation
import RehearsalAudio

@MainActor
public final class StemPlayer: PlaybackYielding {
  public private(set) var state = PlayerState.stopped
  public let durationSec: Double
  public var onFinish: (() -> Void)?
  public var onPause: (() -> Void)?
  public var mix = StemMix() { didSet { applyMix() } }
  /// The pitch shift in semitones, the tempo kept; one shifter after the stems' own mixer, bypassed at 0.
  public var semitones = 0 { didSet { applyPitch() } }

  private let engine = AVAudioEngine()
  private let stemsMixer = AVAudioMixerNode()
  private let shifter = AVAudioUnitTimePitch()
  private var nodes: [Stem: AVAudioPlayerNode] = [:]
  private var files: [Stem: AVAudioFile] = [:]
  private let rate: Double
  private let frames: Int
  private let coordinator: PlaybackCoordinator
  private let session: SessionHost
  private var anchor = 0
  private var resumeFrame = 0
  private var lastFrame = 0
  private var generation = 0

  public init(urls: [Stem: URL], coordinator: PlaybackCoordinator? = nil, session: SessionHost = SystemSession()) throws {
    self.coordinator = coordinator ?? .shared
    self.session = session
    engine.attach(stemsMixer)
    engine.attach(shifter)
    engine.connect(stemsMixer, to: shifter, format: nil)
    engine.connect(shifter, to: engine.mainMixerNode, format: nil)
    for stem in Stem.allCases {
      guard let url = urls[stem] else { throw StemError.unreadable }
      let file = try AVAudioFile(forReading: url)
      let node = AVAudioPlayerNode()
      engine.attach(node)
      engine.connect(node, to: stemsMixer, format: file.processingFormat)
      (files[stem], nodes[stem]) = (file, node)
    }
    let first = files[.drums]!
    rate = first.processingFormat.sampleRate
    frames = Int(files.values.map(\.length).min() ?? 0)
    durationSec = Double(frames) / rate
    applyMix()
    applyPitch()
    session.onInterruption = { [weak self] _ in MainActor.assumeIsolated { self?.pause() } }
    session.observe()
  }

  deinit { session.unobserve() }

  public var positionSec: Double { Double(currentFrame) / rate }

  public func play() throws {
    guard state != .playing else { return }
    coordinator.claim(self)
    try session.activate(recording: false, headsetInput: false)
    if resumeFrame >= frames { resumeFrame = 0 }
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
    resumeFrame = 0
    state = .stopped
    coordinator.release(self)
  }

  public func seek(to sec: Double) {
    resumeFrame = min(max(Int((sec * rate).rounded()), 0), frames)
    if state == .playing { schedule() }
  }

  public func yieldPlayback() { pause() }

  private var currentFrame: Int {
    guard state == .playing else { return resumeFrame }
    guard let node = nodes[.drums], let t = node.lastRenderTime, let p = node.playerTime(forNodeTime: t) else { return lastFrame }
    lastFrame = min(frames, anchor + max(0, Int(p.sampleTime)))
    return lastFrame
  }

  private func schedule() {
    generation += 1
    let g = generation
    let count = frames - resumeFrame
    anchor = resumeFrame
    lastFrame = resumeFrame
    let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.1))
    for stem in Stem.allCases {
      guard let node = nodes[stem], let file = files[stem] else { continue }
      node.stop()
      let report = stem == .drums
      node.scheduleSegment(file, startingFrame: AVAudioFramePosition(resumeFrame), frameCount: AVAudioFrameCount(count), at: nil, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
        guard report else { return }
        Task { @MainActor in self?.segmentDone(g) }
      }
      node.play(at: start)
    }
  }

  private func segmentDone(_ g: Int) {
    guard g == generation, state == .playing else { return }
    halt()
    resumeFrame = frames
    state = .stopped
    coordinator.release(self)
    onFinish?()
  }

  private func halt() {
    generation += 1
    for node in nodes.values { node.stop() }
    engine.pause()
  }

  private func applyPitch() {
    shifter.pitch = Float(semitones * 100)
    shifter.bypass = semitones == 0
  }

  private func applyMix() {
    for (stem, node) in nodes { node.volume = mix.gain(of: stem) }
  }
}
