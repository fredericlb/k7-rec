// Playhead.swift: where a player is after `played` frames of a range, looped or not (pure, so it tests on the Mac).
// What reads wrong: the first pass starts mid-range, every later pass starts at the range's start.

import Foundation

public enum Playhead {
  /// The frame a player stands on after `played` frames since it was scheduled from `from`.
  public static func frame(from: Int, rangeStart: Int, rangeEnd: Int, loops: Bool, played: Int) -> Int {
    let first = max(0, rangeEnd - from)
    if played < first { return from + played }
    guard loops, rangeEnd > rangeStart else { return rangeEnd }
    return rangeStart + (played - first) % (rangeEnd - rangeStart)
  }
}

@MainActor
public protocol PlaybackYielding: AnyObject {
  func yieldPlayback()
}

/// One thing plays at a time app-wide: claiming the floor stops whoever held it.
@MainActor
public final class PlaybackCoordinator {
  public static let shared = PlaybackCoordinator()
  private weak var current: (any PlaybackYielding)?

  public func claim(_ p: any PlaybackYielding) {
    if let c = current, c !== p { c.yieldPlayback() }
    current = p
  }

  public func release(_ p: any PlaybackYielding) {
    if current === p { current = nil }
  }
}
