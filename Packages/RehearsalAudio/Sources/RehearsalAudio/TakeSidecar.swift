// TakeSidecar.swift: what a crashed take needs and its raw file cannot say, written beside the raw file.
// What reads wrong: the raw file is the truth for frames, rate and peak; the sidecar holds only the earlier part.

import Foundation

struct TakeSidecar: Codable, Equatable {
  var intervalMs: Int
  /// The earlier take being continued, as an absolute path and as a name beside the raw file.
  var existingPath: String?
  var existingEnvelope: Envelope?

  init(intervalMs: Int, existing: ExistingTake?) {
    self.intervalMs = intervalMs
    existingPath = existing?.url.path
    existingEnvelope = existing?.envelope
  }

  static func url(for raw: URL) -> URL {
    raw.deletingPathExtension().appendingPathExtension("json")
  }

  func write(for raw: URL) throws {
    try JSONEncoder().encode(self).write(to: Self.url(for: raw), options: .atomic)
  }

  static func read(for raw: URL) -> TakeSidecar? {
    guard let data = try? Data(contentsOf: url(for: raw)) else { return nil }
    return try? JSONDecoder().decode(TakeSidecar.self, from: data)
  }

  static func remove(for raw: URL) {
    try? FileManager.default.removeItem(at: url(for: raw))
  }

  /// The earlier take when its file is still there, found by path or by name beside the raw file.
  func existing(besides raw: URL) -> ExistingTake? {
    guard let path = existingPath, let envelope = existingEnvelope else { return nil }
    let beside = raw.deletingLastPathComponent().appendingPathComponent((path as NSString).lastPathComponent)
    for url in [URL(fileURLWithPath: path), beside] where FileManager.default.fileExists(atPath: url.path) {
      return ExistingTake(url: url, envelope: envelope)
    }
    return nil
  }
}
