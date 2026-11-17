// Bounded.swift: runs one awaited call with a deadline, since a stalled server never answers by itself.
// What a reader gets wrong: the call is abandoned, not cancelled; `onLate` frees what it returns if it still finishes.

import Foundation

enum Bounded {
  /// The result of `body`, or `timeout` after `seconds`; `onLate` gets a result that arrives after that.
  static func run<T>(
    _ seconds: TimeInterval, timeout: @escaping @Sendable () -> Error, onLate: @escaping @Sendable (T) async -> Void = { _ in },
    _ body: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let gate = Gate()
    let boxed: Box<T> = try await withCheckedThrowingContinuation { (done: CheckedContinuation<Box<T>, Error>) in
      Task {
        do {
          let value = Box(try await body())
          if gate.take() { done.resume(returning: value) } else { await onLate(value.value) }
        } catch { if gate.take() { done.resume(throwing: error) } }
      }
      Task {
        try? await Task.sleep(for: .seconds(seconds))
        if gate.take() { done.resume(throwing: timeout()) }
      }
    }
    return boxed.value
  }
}

/// Carries a result the library does not mark Sendable across the one hand-over, to the caller.
struct Box<T>: @unchecked Sendable { let value: T; init(_ value: T) { self.value = value } }

/// A flag taken once, so the call and its deadline cannot both resume the continuation.
final class Gate: @unchecked Sendable {
  private let lock = NSLock()
  private var taken = false

  func take() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if taken { return false }
    taken = true
    return true
  }
}
