// AudioInput.swift: where a take's frames come from, so the recorder's logic runs against a fake on the Mac.
// What reads wrong: frames arrive on the audio thread, mono, in chunks of any size.

import AVFoundation

public protocol AudioInput: AnyObject, Sendable {
  var sampleRate: Double { get }
  /// Called when the input dies mid-take (a route lost, the engine reconfigured).
  var onLost: (@Sendable () -> Void)? { get set }
  func start(_ onFrames: @escaping @Sendable (UnsafeBufferPointer<Float>) -> Void) throws
  func stop()
}

/// The device's microphone through an AVAudioEngine tap, mixed down to mono.
public final class EngineInput: AudioInput, @unchecked Sendable {
  private let lock = NSLock()
  private var engine = AVAudioEngine()
  private var observer: NSObjectProtocol?
  private var lost: (@Sendable () -> Void)?

  public var onLost: (@Sendable () -> Void)? {
    get { lock.withLock { lost } }
    set { lock.withLock { lost = newValue } }
  }

  public init() {}

  public var sampleRate: Double { engine.inputNode.outputFormat(forBus: 0).sampleRate }

  public func start(_ onFrames: @escaping @Sendable (UnsafeBufferPointer<Float>) -> Void) throws {
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.fileReadUnknown) }
    let channels = Int(format.channelCount)
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
      guard let data = buffer.floatChannelData else { return }
      let n = Int(buffer.frameLength)
      if channels == 1 {
        onFrames(UnsafeBufferPointer(start: data[0], count: n))
        return
      }
      var mono = [Float](repeating: 0, count: n)
      for c in 0..<channels { for i in 0..<n { mono[i] += data[c][i] } }
      let k = 1 / Float(channels)
      for i in 0..<n { mono[i] *= k }
      mono.withUnsafeBufferPointer { onFrames($0) }
    }
    observer = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
    ) { [weak self] _ in self?.onLost?() }
    defer { if engine.isRunning == false { stop() } }
    engine.prepare()
    try engine.start()
  }

  public func stop() {
    if let o = observer { NotificationCenter.default.removeObserver(o) }
    observer = nil
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    // A fresh engine per run: one that lived through a media-services reset is unusable.
    engine = AVAudioEngine()
  }
}
