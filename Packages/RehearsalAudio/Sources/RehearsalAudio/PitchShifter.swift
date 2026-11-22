// PitchShifter.swift: Signalsmith Stretch as an in-process effect Audio Unit, so a player's graph shifts pitch
// at the same tempo, one frame out for one frame in. Its output lags by `latencyFrames` while it shifts.
import AVFoundation
import CStretch

/// The shifter a player puts in its graph; 0 semitones lets the sound through untouched.
public final class PitchShifter {
  public let node: AVAudioUnitEffect
  private let unit: StretchUnit

  @MainActor public init() {
    StretchUnit.register
    node = AVAudioUnitEffect(audioComponentDescription: StretchUnit.description)
    unit = node.auAudioUnit as! StretchUnit
  }

  public var semitones = 0 { didSet { unit.core.semitones = semitones } }

  /// Seconds the sound lags the player's own position, 0 when nothing is shifted.
  public var latency: Double {
    guard semitones != 0 else { return 0 }
    return Double(unit.core.latency) / node.outputFormat(forBus: 0).sampleRate
  }
}

/// What the render thread touches: the C shifter, made when render resources are allocated.
final class StretchCore: @unchecked Sendable {
  private var shifter: OpaquePointer?
  private var latencyNow = 0
  var semitones = 0 { didSet { if let shifter { cstretch_set_semitones(shifter, Float(semitones)) } } }
  var latency: Int { latencyNow }

  func configure(channels: Int, rate: Double, maxFrames: Int) {
    release()
    shifter = cstretch_create(Int32(channels), rate, Int32(maxFrames))
    cstretch_set_semitones(shifter, Float(semitones))
    latencyNow = Int(cstretch_latency(shifter))
  }

  func release() {
    if let shifter { cstretch_destroy(shifter) }
    shifter = nil
  }

  func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
    guard let shifter else { return }
    // The buffers follow the list's count in memory; walked by hand, as Catalyst lacks the overlay's pointer type.
    let count = min(Int(list.pointee.mNumberBuffers), 8)
    let first = (UnsafeMutableRawPointer(list) + MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)!).assumingMemoryBound(to: AudioBuffer.self)
    withUnsafeTemporaryAllocation(of: UnsafeMutablePointer<Float>?.self, capacity: 8) { channels in
      for k in 0..<count {
        guard let data = first[k].mData else { return }
        channels[k] = data.assumingMemoryBound(to: Float.self)
      }
      cstretch_process(shifter, channels.baseAddress, Int32(frames))
    }
  }

  deinit { release() }
}

/// The Audio Unit: one input bus, one output bus of the same format, processed in place.
final class StretchUnit: AUAudioUnit, @unchecked Sendable {
  static let description = AudioComponentDescription(
    componentType: kAudioUnitType_Effect, componentSubType: fourCC("k7st"), componentManufacturer: fourCC("K7rc"),
    componentFlags: 0, componentFlagsMask: 0)
  static let register: Void = AUAudioUnit.registerSubclass(StretchUnit.self, as: description, name: "K7: Pitch", version: 1)

  let core = StretchCore()
  private var input: AUAudioUnitBus!
  private var output: AUAudioUnitBus!
  private var inputs: AUAudioUnitBusArray!
  private var outputs: AUAudioUnitBusArray!

  override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
    try super.init(componentDescription: componentDescription, options: options)
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    input = try AUAudioUnitBus(format: format)
    output = try AUAudioUnitBus(format: format)
    inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [input])
    outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [output])
    maximumFramesToRender = 4096
  }

  override var inputBusses: AUAudioUnitBusArray { inputs }
  override var outputBusses: AUAudioUnitBusArray { outputs }
  override var canProcessInPlace: Bool { true }

  override func allocateRenderResources() throws {
    try super.allocateRenderResources()
    core.configure(channels: Int(output.format.channelCount), rate: output.format.sampleRate, maxFrames: Int(maximumFramesToRender))
  }

  override func deallocateRenderResources() {
    core.release()
    super.deallocateRenderResources()
  }

  override var internalRenderBlock: AUInternalRenderBlock {
    let core = core
    return { flags, timestamp, frames, _, output, _, pull in
      guard let pull else { return kAudioUnitErr_NoConnection }
      let status = pull(flags, timestamp, frames, 0, output)
      guard status == noErr else { return status }
      core.process(output, frames: Int(frames))
      return noErr
    }
  }
}

private func fourCC(_ s: String) -> FourCharCode { s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) } }
