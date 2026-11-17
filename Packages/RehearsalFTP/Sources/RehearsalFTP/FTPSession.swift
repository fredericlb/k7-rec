// FTPSession.swift: an FTPS login that lists folders and moves files, over passive data connections.
// What a reader gets wrong: there is no plain mode; the control and every data connection are TLS, and a data
// connection resumes the control connection's TLS session, which servers that ask for it require.

import Foundation

/// How TLS starts: explicit asks the server with AUTH TLS on the usual port, implicit is TLS from the first byte.
public enum FTPSecurity: String, Sendable, Equatable, CaseIterable {
  case explicit, implicit

  public var defaultPort: Int { self == .explicit ? 21 : 990 }
}

public struct FTPConfig: Sendable, Equatable {
  public var host: String
  public var port: Int
  public var user: String
  public var password: String
  public var security: FTPSecurity
  /// Accepts a certificate the system does not trust (a self-signed one); the connection is still encrypted.
  public var trustAnyCertificate: Bool

  public init(
    host: String, port: Int? = nil, user: String = "anonymous", password: String = "",
    security: FTPSecurity = .explicit, trustAnyCertificate: Bool = false
  ) {
    (self.host, self.user, self.password, self.security, self.trustAnyCertificate) = (host, user, password, security, trustAnyCertificate)
    self.port = port ?? security.defaultPort
  }
}

public struct FTPEntry: Sendable, Equatable, Identifiable {
  public var name: String
  public var isDirectory: Bool
  public var size: Int64?
  public var id: String { name }

  public init(name: String, isDirectory: Bool, size: Int64? = nil) { (self.name, self.isDirectory, self.size) = (name, isDirectory, size) }
}

public enum FTPError: Error, Equatable, LocalizedError {
  case unreachable(String)
  case refused(code: Int, text: String)
  case loginFailed
  case badReply(String)
  case tls(String)
  case untrustedCertificate(String)
  case noTLS

  public var errorDescription: String? {
    switch self {
    case .unreachable(let why): "The server could not be reached: \(why)"
    case .loginFailed: "The server refused the user name or the password."
    case .refused(let code, let text): "The server answered \(code) \(text)"
    case .badReply(let text): "The server sent something unexpected: \(text)"
    case .tls(let why): "The secure connection failed: \(why)"
    case .untrustedCertificate(let why): "The server's certificate is not trusted (\(why)). Turn on \"Accept an untrusted certificate\" if you know this server."
    case .noTLS: "The server does not offer TLS, so it cannot be used for FTPS."
    }
  }
}

public final class FTPSession: @unchecked Sendable {
  private let control: Connection
  private let config: FTPConfig
  private var peerID: String { "\(config.host):\(config.port)" }

  private init(control: Connection, config: FTPConfig) { (self.control, self.config) = (control, config) }

  /// Connects and logs in; the session is ready for `list` and `download`.
  public static func open(_ config: FTPConfig) async throws -> FTPSession {
    let control = Connection(host: config.host, port: UInt16(clamping: config.port))
    let session = FTPSession(control: control, config: config)
    do {
      try await control.open()
      if config.security == .implicit { try await control.startTLS(peerID: session.peerID, trustAnyCertificate: config.trustAnyCertificate) }
      _ = try await session.reply(expecting: 2)
      if config.security == .explicit {
        let auth = try await session.command("AUTH TLS")
        guard auth.code == 234 else { throw FTPError.noTLS }
        try await control.startTLS(peerID: session.peerID, trustAnyCertificate: config.trustAnyCertificate)
      }
      // Protection buffer size 0 and private data channels: the listings and the files are encrypted too.
      _ = try await session.command("PBSZ 0")
      let prot = try await session.command("PROT P")
      guard prot.code / 100 == 2 else { throw FTPError.refused(code: prot.code, text: prot.text) }
      var r = try await session.command("USER \(config.user)")
      if r.code == 331 { r = try await session.command("PASS \(config.password)") }
      guard r.code / 100 == 2 else { throw r.code == 530 || r.code == 331 ? FTPError.loginFailed : FTPError.refused(code: r.code, text: r.text) }
      _ = try await session.command("TYPE I")
      _ = try? await session.command("OPTS UTF8 ON")
    } catch {
      control.close()
      throw error
    }
    return session
  }

  public func close() {
    Task { [control] in
      try? await control.send("QUIT\r\n")
      control.close()
    }
  }

  /// The folder's entries, folders first; MLSD when the server has it, LIST otherwise.
  public func list(_ path: String) async throws -> [FTPEntry] {
    let clean = try Self.clean(path)
    let facts = try await transfer("MLSD \(clean)") { try await Self.collect($0) }
    if let text = facts { return Self.sorted(FTPListing.parseMLSD(text)) }
    guard let text = try await transfer("LIST \(clean)", { try await Self.collect($0) }) else {
      throw FTPError.refused(code: 550, text: "cannot list \(path)")
    }
    return Self.sorted(FTPListing.parseList(text))
  }

  /// Streams a file to `url`; `progress` gets the bytes written so far. A partial file is removed on failure.
  public func download(_ path: String, to url: URL, progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws {
    let clean = try Self.clean(path)
    let fm = FileManager.default
    fm.createFile(atPath: url.path, contents: nil)
    do {
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      var total: Int64 = 0
      let done = try await transfer("RETR \(clean)") { data in
        for try await chunk in data.chunks() {
          try handle.write(contentsOf: chunk)
          total += Int64(chunk.count)
          progress(total)
        }
        return true
      }
      guard done != nil else { throw FTPError.refused(code: 550, text: "cannot read \(path)") }
    } catch {
      try? fm.removeItem(at: url)
      throw error
    }
  }

  /// Puts `data` at the end of the file, creating it when it is not there (`APPE`).
  public func append(_ data: Data, to path: String) async throws { try await send(data, "APPE", path) }

  /// Writes `data` as the whole file (`STOR`), replacing one that is there.
  public func upload(_ data: Data, to path: String) async throws { try await send(data, "STOR", path) }

  private func send(_ data: Data, _ verb: String, _ path: String) async throws {
    let clean = try Self.clean(path)
    let done: Bool? = try await transfer("\(verb) \(clean)") { conn in
      try await conn.send(data)
      try await conn.finish()
      return true
    }
    guard done != nil else { throw FTPError.refused(code: 550, text: "cannot write \(path)") }
  }

  // MARK: protocol

  /// Runs `body` over a fresh passive data connection; nil when the server refused the command (a 4xx or 5xx).
  private func transfer<T>(_ command: String, _ body: (Connection) async throws -> T) async throws -> T? {
    let data = try await passive()
    defer { data.close() }
    let first = try await self.command(command)
    guard first.code == 125 || first.code == 150 else {
      if first.code >= 400 { return nil }
      throw FTPError.badReply("\(first.code) \(first.text)")
    }
    // The server waits for the handshake once it has answered 150.
    try await data.startTLS(peerID: peerID, trustAnyCertificate: config.trustAnyCertificate)
    let result = try await body(data)
    data.close()
    let end = try await reply()
    guard end.code / 100 == 2 else { throw FTPError.refused(code: end.code, text: end.text) }
    return result
  }

  private func passive() async throws -> Connection {
    var port: Int?
    let extended = try await command("EPSV")
    if extended.code == 229 { port = Self.number(after: "(|||", in: extended.text) }
    if port == nil {
      let r = try await command("PASV")
      guard r.code == 227, let p = Self.passivePort(r.text) else { throw FTPError.refused(code: r.code, text: r.text) }
      port = p
    }
    let data = Connection(host: config.host, port: UInt16(clamping: port ?? 0))
    try await data.open()
    return data
  }

  func command(_ text: String) async throws -> (code: Int, text: String) {
    try await control.send(text + "\r\n")
    return try await reply()
  }

  private func reply(expecting hundred: Int? = nil) async throws -> (code: Int, text: String) {
    var line = try await control.line()
    guard line.count >= 3, let code = Int(line.prefix(3)) else { throw FTPError.badReply(line) }
    var text = String(line.dropFirst(4))
    // A multi-line reply is "123-..." up to a line that starts "123 ".
    if line.dropFirst(3).first == "-" {
      while true {
        line = try await control.line()
        if line.hasPrefix("\(code) ") { text += "\n" + line.dropFirst(4); break }
        text += "\n" + line
      }
    }
    if let hundred, code / 100 != hundred { throw FTPError.refused(code: code, text: text) }
    return (code, text)
  }

  // MARK: helpers

  private static func clean(_ path: String) throws -> String {
    guard !path.contains("\r"), !path.contains("\n") else { throw FTPError.badReply("a path with a line break") }
    return path.isEmpty ? "/" : path
  }

  private static func collect(_ data: Connection) async throws -> String {
    var all = Data()
    for try await chunk in data.chunks() { all.append(chunk) }
    return String(decoding: all, as: UTF8.self)
  }

  private static func sorted(_ entries: [FTPEntry]) -> [FTPEntry] {
    entries.sorted { ($0.isDirectory ? 0 : 1, $0.name.lowercased()) < ($1.isDirectory ? 0 : 1, $1.name.lowercased()) }
  }

  private static func number(after marker: String, in text: String) -> Int? {
    guard let r = text.range(of: marker) else { return nil }
    return Int(text[r.upperBound...].prefix { $0.isNumber })
  }

  /// The port of "227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)"; the address is ignored, the control host is used.
  static func passivePort(_ text: String) -> Int? {
    guard let open = text.firstIndex(of: "("), let close = text.firstIndex(of: ")"), open < close else { return nil }
    let n = text[text.index(after: open)..<close].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    return n.count == 6 ? n[4] * 256 + n[5] : nil
  }
}

extension Connection {
  /// The bytes of a data connection until the server closes it.
  func chunks() -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          while let data = try await receive() { if !data.isEmpty { continuation.yield(data) } }
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
