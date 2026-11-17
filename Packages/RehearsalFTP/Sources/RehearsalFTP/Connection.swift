// Connection.swift: one TCP connection, awaited, that can become TLS in place, with CRLF lines.
// What a reader gets wrong: reads block a thread of the connection's own queue; a stalled peer is cut by the
// socket's timeout, and `close()` from anywhere wakes a blocked read.

import Foundation

final class Connection: @unchecked Sendable {
  let host: String
  let port: UInt16
  private let queue = DispatchQueue(label: "rehearsal.ftp.connection")
  private let lock = NSLock()
  private var socket: SecureSocket?
  private var buffer = Data()
  private var closed = false

  init(host: String, port: UInt16) { (self.host, self.port) = (host, port) }

  deinit { close() }

  func open() async throws {
    let (host, port) = (host, port)
    let s = try await run { try SecureSocket.connect(host: host, port: port) }
    lock.withLock { socket = s }
    if lock.withLock({ closed }) { s.close() }
  }

  /// Upgrades the connection to TLS; `peerID` lets a later connection resume this session.
  func startTLS(peerID: String, trustAnyCertificate: Bool) async throws {
    let s = try current()
    let host = host
    try await run { try s.startTLS(host: host, peerID: peerID, trustAnyCertificate: trustAnyCertificate) }
  }

  func send(_ text: String) async throws { try await send(Data(text.utf8)) }

  func send(_ data: Data) async throws {
    let s = try current()
    try await run { try s.write(data) }
  }

  /// Tells the peer nothing more is coming, without closing: the peer's answer can still be read.
  func finish() async throws {
    let s = try current()
    await run { s.finish() }
  }

  /// The next bytes, nil once the peer closed its side.
  func receive() async throws -> Data? {
    let s = try current()
    return try await run { try s.read(max: 64 * 1024) }
  }

  /// A line without its line end; throws when the peer closed before one.
  func line() async throws -> String {
    while true {
      if let end = lock.withLock({ buffer.firstIndex(of: 0x0A) }) {
        let raw = lock.withLock { () -> Data in
          let out = buffer[buffer.startIndex..<end]
          buffer.removeSubrange(buffer.startIndex...end)
          return Data(out)
        }
        var text = String(decoding: raw, as: UTF8.self)
        if text.hasSuffix("\r") { text.removeLast() }
        return text
      }
      guard let more = try await receive() else { throw FTPError.unreachable("the server closed the connection") }
      lock.withLock { buffer.append(more) }
    }
  }

  func close() {
    let s = lock.withLock { () -> SecureSocket? in closed = true; return socket }
    s?.close()
  }

  private func current() throws -> SecureSocket {
    try lock.withLock {
      guard let socket, !closed else { throw FTPError.unreachable("the connection is closed") }
      return socket
    }
  }

  private func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { done in
      queue.async { done.resume(with: Result { try body() }) }
    }
  }

  private func run(_ body: @escaping @Sendable () -> Void) async {
    await withCheckedContinuation { done in queue.async { body(); done.resume() } }
  }
}
