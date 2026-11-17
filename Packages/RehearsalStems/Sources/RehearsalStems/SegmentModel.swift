// SegmentModel.swift: what the separator asks of a model, and the Core ML model that answers it.
// What a reader gets wrong: the model sees one fixed-length segment of stereo audio, never a whole song.

import CoreML
import Foundation

public protocol SegmentModel: Sendable {
  var sampleRate: Double { get }
  /// The frames of one segment, fixed by the model's input.
  var segmentFrames: Int { get }
  /// `mix` is [channel][frame] with `segmentFrames` frames; the answer is [stem][channel][frame], in `Stem` order.
  func separate(_ mix: [[Float]]) throws -> [[[Float]]]
}

/// A compiled Core ML model: `[1, 2, N]` in, `[1, stems * 2, N]` or `[1, stems, 2, N]` out, Float32 at 44.1 kHz (docs/stems.md).
public final class CoreMLSegmentModel: SegmentModel, @unchecked Sendable {
  public let sampleRate = 44_100.0
  public let segmentFrames: Int
  private let model: MLModel
  private let inputName: String
  private let outputName: String

  /// `url` is a `.mlmodelc`; a `.mlpackage` goes through `compile` first.
  public init(url: URL, computeUnits: MLComputeUnits = .cpuOnly) throws {
    let config = MLModelConfiguration()
    config.computeUnits = computeUnits
    model = try MLModel(contentsOf: url, configuration: config)
    let description = model.modelDescription
    guard let input = description.inputDescriptionsByName.first(where: { $0.value.multiArrayConstraint != nil }),
      let shape = input.value.multiArrayConstraint?.shape.map(\.intValue), shape.count >= 2, shape[shape.count - 2] == 2,
      let last = shape.last, last > 0, let output = description.outputDescriptionsByName.keys.sorted().first
    else { throw StemError.modelMissing }
    (inputName, outputName, segmentFrames) = (input.key, output, last)
  }

  public static func compile(_ package: URL) async throws -> URL { try await MLModel.compileModel(at: package) }

  public func separate(_ mix: [[Float]]) throws -> [[[Float]]] {
    let n = segmentFrames
    let input = try MLMultiArray(shape: [1, 2, NSNumber(value: n)], dataType: .float32)
    let strides = input.strides.map(\.intValue)
    let base = input.dataPointer.assumingMemoryBound(to: Float.self)
    for c in 0..<2 { for i in 0..<n { base[c * strides[1] + i * strides[2]] = mix[c][i] } }
    let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: input)]))
    guard let array = result.featureValue(for: outputName)?.multiArrayValue else { throw StemError.unreadable }
    return try Self.read(array, frames: n)
  }

  /// The trailing dimensions of `array` as [stem][channel][frame]; paired channels (stem * 2 + channel) or a stem axis.
  static func read(_ array: MLMultiArray, frames n: Int) throws -> [[[Float]]] {
    let shape = array.shape.map(\.intValue), strides = array.strides.map(\.intValue)
    guard shape.count >= 2, shape[shape.count - 1] == n else { throw StemError.unreadable }
    let rank = shape.count
    let separate = rank >= 3 && shape[rank - 2] == 2
    let stems = separate ? shape[rank - 3] : shape[rank - 2] / 2
    guard stems > 0 else { throw StemError.unreadable }
    let (stemStride, channelStride, frameStride) = separate
      ? (strides[rank - 3], strides[rank - 2], strides[rank - 1]) : (2 * strides[rank - 2], strides[rank - 2], strides[rank - 1])
    var out = [[[Float]]](repeating: [[Float]](repeating: [Float](repeating: 0, count: n), count: 2), count: stems)
    for s in 0..<stems {
      for c in 0..<2 {
        let at = s * stemStride + c * channelStride
        if array.dataType == .float32, frameStride == 1 {
          let p = array.dataPointer.assumingMemoryBound(to: Float.self) + at
          out[s][c] = Array(UnsafeBufferPointer(start: p, count: n))
        } else {
          for i in 0..<n { out[s][c][i] = array[at + i * frameStride].floatValue }
        }
      }
    }
    return out
  }
}
