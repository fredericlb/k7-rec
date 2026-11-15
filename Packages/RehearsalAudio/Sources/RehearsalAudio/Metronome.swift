// Metronome.swift: a click on the audio clock, a port of useMetronome.ts (a click every beat, an accent each bar).
// What reads wrong: a beat callback fires from the main queue just after its buffer, not at the exact frame.

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

@MainActor
public final class Metronome {
  public private(set) var state: MetronomeState?
  /// Called as each click sounds, `downbeat` on the first of a bar.
  public var onBeat: ((Bool) -> Void)?
  private var engine: AVAudioEngine?

  public init() {}

  public func start(bpm: Double, startSec: Double) throws {
    stop()
    guard bpm > 0 else { return }
    try AudioSessionConfig.activate()
    let engine = AVAudioEngine()
    let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    var gen = ClickGenerator(bpm: bpm, sampleRate: rate > 0 ? rate : 44_100)
    let format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 44_100, channels: 1)!
    let src = AVAudioSourceNode(format: format) { [weak self] _, _, frames, abl in
      let list = UnsafeMutableAudioBufferListPointer(abl)
      guard let p = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
      let beats = gen.render(into: p, frames: Int(frames))
      for b in beats { DispatchQueue.main.async { MainActor.assumeIsolated { self?.onBeat?(b.downbeat) } } }
      return noErr
    }
    engine.attach(src)
    engine.connect(src, to: engine.mainMixerNode, format: format)
    try engine.start()
    self.engine = engine
    state = MetronomeState(bpm: bpm, startSec: startSec)
  }

  public func stop() {
    engine?.stop()
    engine = nil
    state = nil
  }
}
