// SFTPSession.swift: one SFTP login over SSH (Citadel) that lists folders and reads and writes files.
// What a reader gets wrong: the first host key is trusted and handed back; a later key that differs is refused.

@preconcurrency import Citadel
import CryptoKit
import Foundation
import NIOCore
@preconcurrency import NIOSSH

public final class SFTPSession: @unchecked Sendable {
  private let ssh: SSHClient
  private let sftp: SFTPClient
  /// The fingerprint of the key the server showed, for the caller to keep and pass as `pinnedKey` next time.
  public let hostKey: String
  /// Seconds without an answer after which a call gives up.
  static let idle: TimeInterval = 20
  private static let chunk: UInt32 = 32_768

  private init(ssh: SSHClient, sftp: SFTPClient, hostKey: String) { (self.ssh, self.sftp, self.hostKey) = (ssh, sftp, hostKey) }

  /// Connects and logs in; the session is ready for `list`, `download`, `upload` and `append`.
  public static func open(_ config: SFTPConfig) async throws -> SFTPSession {
    let check = HostKeyCheck(pinned: config.pinnedKey)
    let method = try authentication(config)
    let ssh: SSHClient
    do {
      ssh = try await Bounded.run(idle + 5, timeout: { SFTPError.unreachable("no answer") }, onLate: { (c: SSHClient) in try? await c.close() }) {
        try await SSHClient.connect(
          host: config.host, port: config.port, authenticationMethod: method, hostKeyValidator: .custom(check), reconnect: .never,
          connectTimeout: .seconds(15))
      }
    } catch { throw map(error, check) }
    do {
      let sftp = try await Bounded.run(idle, timeout: { SFTPError.unreachable("no answer") }) { try await ssh.openSFTP() }
      return SFTPSession(ssh: ssh, sftp: sftp, hostKey: check.seen ?? "")
    } catch {
      try? await ssh.close()
      throw map(error, check)
    }
  }

  public func close() {
    Task { [ssh, sftp] in
      try? await sftp.close()
      try? await ssh.close()
    }
  }

  /// The folder's entries, folders first; a link is resolved to what it points at.
  public func list(_ path: String) async throws -> [SFTPEntry] {
    let names = try await call { try await $0.listDirectory(atPath: path) }
    var out: [SFTPEntry] = []
    for part in names.flatMap(\.components) where part.filename != "." && part.filename != ".." {
      var folder = false
      switch SFTPLogic.kind(permissions: part.attributes.permissions) {
      case .folder: folder = true
      case .file: break
      case .link:
        let target = SFTPLogic.join(path, part.filename)
        let attrs = try? await call { try await $0.getAttributes(at: target) }
        folder = SFTPLogic.kind(permissions: attrs?.permissions) == .folder
      }
      out.append(SFTPEntry(name: part.filename, isDirectory: folder, size: part.attributes.size.map { Int64($0) }))
    }
    return SFTPLogic.sorted(out)
  }

  /// Streams a file to `url`; `progress` gets the bytes written so far. A partial file is removed on failure.
  public func download(_ path: String, to url: URL, progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws {
    let fm = FileManager.default
    fm.createFile(atPath: url.path, contents: nil)
    do {
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      let file = try await call { try await $0.openFile(filePath: path, flags: .read) }
      var offset: UInt64 = 0
      do {
        while true {
          let at = offset
          let data = try await Bounded.run(Self.idle, timeout: { SFTPError.unreachable("the transfer stalled") }) {
            try await file.read(from: at, length: Self.chunk)
          }
          if data.readableBytes == 0 { break }
          try handle.write(contentsOf: Data(buffer: data))
          offset += UInt64(data.readableBytes)
          progress(Int64(offset))
        }
      } catch {
        try? await file.close()
        throw error
      }
      try? await file.close()
    } catch {
      try? fm.removeItem(at: url)
      throw Self.refusal(error)
    }
  }

  /// Writes `data` as the whole file, replacing one that is there.
  public func upload(_ data: Data, to path: String) async throws {
    try await write(data, to: path, flags: [.write, .create, .truncate], atEnd: false)
  }

  /// Puts `data` at the end of the file, creating it when it is not there.
  public func append(_ data: Data, to path: String) async throws {
    try await write(data, to: path, flags: [.write, .create], atEnd: true)
  }

  // MARK: helpers

  private func write(_ data: Data, to path: String, flags: SFTPOpenFileFlags, atEnd: Bool) async throws {
    try await call { sftp in
      let file = try await sftp.openFile(filePath: path, flags: flags)
      do {
        // Writing at the size, not with the append flag, which some servers ignore.
        let start = atEnd ? (try await file.readAttributes().size ?? 0) : 0
        try await file.write(ByteBuffer(data: data), at: start)
        try await file.close()
      } catch {
        try? await file.close()
        throw error
      }
    }
  }

  /// One SFTP request with the idle deadline; failures read as ours.
  private func call<T: Sendable>(_ body: @escaping @Sendable (SFTPClient) async throws -> T) async throws -> T {
    do {
      return try await Bounded.run(Self.idle, timeout: { SFTPError.unreachable("no answer") }) { [sftp] in try await body(sftp) }
    } catch { throw Self.refusal(error) }
  }

  private static func refusal(_ error: Error) -> Error {
    if error is SFTPError { return error }
    if let status = error as? Citadel.SFTPError {
      if case .errorStatus(let s) = status { return SFTPError.refused(s.message.isEmpty ? "\(s.errorCode)" : s.message) }
      return SFTPError.unreachable("\(status)")
    }
    if let status = error as? SFTPMessage.Status { return SFTPError.refused(status.message.isEmpty ? "\(status.errorCode)" : status.message) }
    return error
  }

  private static func authentication(_ c: SFTPConfig) throws -> SSHAuthenticationMethod {
    if c.password.isEmpty, let pem = c.privateKey {
      do { return .ed25519(username: c.user, privateKey: try Curve25519.Signing.PrivateKey(sshEd25519: pem)) }
      catch { throw SFTPError.refused("the private key could not be read") }
    }
    return .passwordBased(username: c.user, password: c.password)
  }

  private static func map(_ error: Error, _ check: HostKeyCheck) -> Error {
    if let changed = check.changed { return changed }
    if let e = error as? SFTPError { return e }
    if error is AuthenticationFailed { return SFTPError.loginFailed }
    if let e = error as? SSHClientError, e == .allAuthenticationOptionsFailed { return SFTPError.loginFailed }
    if let posix = error as? IOError { return SFTPError.unreachable(String(cString: strerror(posix.errnoCode))) }
    return SFTPError.unreachable("the connection failed (\(type(of: error)))")
  }
}

/// Accepts the first key, remembers what the server showed, and refuses a key that is not the pinned one.
final class HostKeyCheck: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private let pinned: String?
  private var shown: String?
  private var mismatch: SFTPError?

  init(pinned: String?) { self.pinned = pinned.flatMap { $0.isEmpty ? nil : $0 } }

  var seen: String? { lock.withLock { shown } }
  var changed: SFTPError? { lock.withLock { mismatch } }

  func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
    guard let print = SFTPLogic.fingerprint(openSSHKey: String(openSSHPublicKey: hostKey)) else {
      return validationCompletePromise.fail(SFTPError.unreachable("an unreadable host key"))
    }
    lock.withLock { shown = print }
    if let pinned, pinned != print {
      let error = SFTPError.hostKeyChanged(expected: pinned, got: print)
      lock.withLock { mismatch = error }
      validationCompletePromise.fail(error)
    } else {
      validationCompletePromise.succeed(())
    }
  }
}
