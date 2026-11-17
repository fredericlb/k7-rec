// Types.swift: what a caller gives and gets back from an SFTP session, and the ways it fails.
// What a reader gets wrong: the host key is pinned by the caller; nil means "first connection, trust and tell me".

import Foundation

public struct SFTPConfig: Sendable, Equatable {
  public var host: String
  public var port: Int
  public var user: String
  public var password: String
  /// An OpenSSH ed25519 private key (PEM), tried when the password is empty.
  public var privateKey: String?
  /// The host key fingerprint ("SHA256:...") kept from the first connection; nil on the first one.
  public var pinnedKey: String?

  public init(host: String, port: Int = 22, user: String, password: String = "", privateKey: String? = nil, pinnedKey: String? = nil) {
    (self.host, self.port, self.user, self.password, self.privateKey, self.pinnedKey) = (host, port, user, password, privateKey, pinnedKey)
  }
}

public struct SFTPEntry: Sendable, Equatable, Identifiable {
  public var name: String
  public var isDirectory: Bool
  public var size: Int64?
  public var id: String { name }

  public init(name: String, isDirectory: Bool, size: Int64? = nil) { (self.name, self.isDirectory, self.size) = (name, isDirectory, size) }
}

public enum SFTPError: Error, Equatable, LocalizedError {
  case unreachable(String)
  case loginFailed
  case hostKeyChanged(expected: String, got: String)
  case refused(String)

  public var errorDescription: String? {
    switch self {
    case .unreachable(let why): "The server could not be reached: \(why)"
    case .loginFailed: "The server refused the user name, the password or the key."
    case .hostKeyChanged(let expected, let got):
      "The server's identity changed. Expected \(expected) but it showed \(got). Disconnect and connect again only if you trust the change."
    case .refused(let why): "The server refused: \(why)"
    }
  }
}
