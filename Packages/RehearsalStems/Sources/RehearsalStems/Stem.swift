// Stem.swift: the four parts a song is split into, and where a song folder keeps them.
// What a reader gets wrong: the case order is the model's output order, so it is part of the model contract.

import Foundation

public enum Stem: String, CaseIterable, Sendable, Hashable, Identifiable {
  case drums, bass, other, vocals

  public var id: String { rawValue }
  public var title: String { rawValue.capitalized }
  public var fileName: String { rawValue + ".m4a" }

  /// The folder of a song folder that holds the stems.
  public static let folderName = "stems"

  public static func folder(in song: URL) -> URL { song.appendingPathComponent(folderName, isDirectory: true) }

  /// The stems of a song folder when all four files are there, nil otherwise (a part is no stem set).
  public static func existing(in song: URL) -> [Stem: URL]? {
    let dir = folder(in: song)
    var out: [Stem: URL] = [:]
    for stem in allCases {
      let url = dir.appendingPathComponent(stem.fileName)
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      out[stem] = url
    }
    return out
  }
}

/// What a stem set has to say in the sheet: how it fails.
public enum StemError: Error, Equatable, Sendable {
  case modelMissing
  case wrongStemCount(Int)
  case unreadable
}

/// How loud each stem plays: a level, a mute, a solo. A solo wins over a mute.
public struct StemMix: Equatable, Sendable {
  public var levels: [Stem: Float] = [:]
  public var muted: Set<Stem> = []
  public var solo: Set<Stem> = []

  public init() {}

  public func level(of stem: Stem) -> Float { levels[stem] ?? 1 }

  /// The gain a stem's player node gets: its level, or 0 when it is muted or another one is solo.
  public func gain(of stem: Stem) -> Float {
    if !solo.isEmpty { return solo.contains(stem) ? level(of: stem) : 0 }
    return muted.contains(stem) ? 0 : level(of: stem)
  }

  public mutating func setLevel(_ value: Float, of stem: Stem) { levels[stem] = min(1, max(0, value)) }
  public mutating func toggleMute(_ stem: Stem) { if !muted.insert(stem).inserted { muted.remove(stem) } }
  public mutating func toggleSolo(_ stem: Stem) { if !solo.insert(stem).inserted { solo.remove(stem) } }
}
