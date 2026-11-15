// Metronome.swift: a click on the audio clock, a port of useMetronome.ts (a click every beat, an accent each bar).
// What reads wrong: a beat callback is timed from the session's latency, so it is close to the click, not exact.

import AVFoundation

/// A running metronome: tempo plus the waveform-timeline position it started at.
public struct MetronomeState: Equatable, Sendable {
  public var bpm: Double
  public var startSec: Double
}

/// The samples of the click, generated frame by frame; one value per metronome run.
public struct ClickGenerator: Sendable {
  public static let beatsPerBar = 4
  public static let clickSec = 0.06
  public static let leadSec = 0.05

  private let rate: Double
  private let period: Double
  private var frame = 0
  private var nextBeat: Double
  private var beat = 0
  private var active: (start: Int, accent: Bool)?

  public init(bpm: Double, sampleRate: Double) {
    rate = sampleRate
    period = 60 / bpm * sampleRate
    nextBeat = Self.leadSec * sampleRate
  }

  /// Fills `out` and returns the frames, within it, where a beat began, with whether it is a downbeat.
  public mutating func render(into out: UnsafeMutablePointer<Float>, frames: Int) -> [(frame: Int, downbeat: Bool)] {
    var beats: [(Int, Bool)] = []
    for i in 0..<frames {
      if Double(frame) >= nextBeat {
        let accent = beat % Self.beatsPerBar == 0
        active = (frame, accent)
        beats.append((i, accent))
        beat += 1
        nextBeat += period
      }
      out[i] = sample()
      frame += 1
    }
    return beats
  }

  private func sample() -> Float {
    guard let a = active else { return 0 }
    let t = Double(frame - a.start) / rate
    if t >= Self.clickSec { return 0 }
    let peak = a.accent ? 0.5 : 0.22
    let env = peak * pow(0.001 / peak, t / Self.clickSec)
    return Float(env * sin(2 * Double.pi * (a.accent ? 1600 : 1000) * t))
  }
}

/// The generator the render block owns; only the audio thread touches it once the engine runs.
private final class GeneratorBox: @unchecked Sendable {
  var generator: ClickGenerator
  init(_ g: ClickGenerator) { generator = g }
}

@MainActor
public final class Metronome {
  public private(set) var state: MetronomeState?
  /// Called as each click reaches the speaker, `downbeat` on the first of a bar; never after `stop()`.
  public var onBeat: ((Bool) -> Void)?
  /// Called when the system stopped the click (a call, a route change), never from `stop()`.
  public var onHalt: (() -> Void)?
  private var engine: AVAudioEngine?
  private let session: SessionHost
  private var configObserver: NSObjectProtocol?
  private var runID = 0

  public init(session: SessionHost = SystemSession()) {
    self.session = session
    session.onInterruption = { [weak self] _ in MainActor.assumeIsolated { self?.halt() } }
  }

  public func start(bpm: Double, startSec: Double) throws {
    stop()
    guard bpm > 0 else { return }
    try session.activate(recording: false, headsetInput: false)
    session.observe()
    let engine = AVAudioEngine()
    let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    let sampleRate = rate > 0 ? rate : 44_100
    let run = runID
    let lead = Self.outputLead()
    let report: @Sendable (Bool, Double) -> Void = { [weak self] downbeat, delay in
      DispatchQueue.main.asyncAfter(deadline: .now() + lead + delay) {
        MainActor.assumeIsolated {
          guard let self, self.runID == run else { return }
          self.onBeat?(downbeat)
        }
      }
    }
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let src = AVAudioSourceNode(format: format, renderBlock: Self.makeRender(ClickGenerator(bpm: bpm, sampleRate: sampleRate), sampleRate, report))
    engine.attach(src)
    engine.connect(src, to: engine.mainMixerNode, format: format)
    configObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.halt() } }
    try engine.start()
    self.engine = engine
    state = MetronomeState(bpm: bpm, startSec: startSec)
  }

  private func halt() {
    guard engine != nil else { return }
    stop()
    onHalt?()
  }

  public func stop() {
    runID += 1
    session.unobserve()
    if let o = configObserver { NotificationCenter.default.removeObserver(o) }
    configObserver = nil
    engine?.stop()
    engine = nil
    state = nil
  }

  /// How long after rendering a click reaches the speaker: the IO buffer plus the output's own latency.
  private static func outputLead() -> Double {
    #if os(iOS)
    let s = AVAudioSession.sharedInstance()
    return s.outputLatency + s.ioBufferDuration
    #else
    return 0
    #endif
  }

  private nonisolated static func makeRender(
    _ generator: ClickGenerator, _ rate: Double, _ report: @escaping @Sendable (Bool, Double) -> Void
  ) -> AVAudioSourceNodeRenderBlock {
    let box = GeneratorBox(generator)
    return { _, _, frames, abl in
      let list = UnsafeMutableAudioBufferListPointer(abl)
      guard let p = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
      for b in box.generator.render(into: p, frames: Int(frames)) { report(b.downbeat, Double(b.frame) / rate) }
      return noErr
    }
  }
}
