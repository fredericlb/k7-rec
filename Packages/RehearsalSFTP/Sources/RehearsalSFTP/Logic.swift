// Logic.swift: the pure parts of the SFTP client: host key fingerprints, entries and their order.
// What a reader gets wrong: a symlink is neither a folder nor a file until it is resolved, so it is told apart here.

import CryptoKit
import Foundation

enum SFTPLogic {
  /// "SHA256:<base64 without padding>" of an OpenSSH public key line ("ssh-ed25519 AAAA... comment"); nil when it is not one.
  static func fingerprint(openSSHKey line: String) -> String? {
    let parts = line.split(separator: " ")
    guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return nil }
    let text = Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    return "SHA256:" + text
  }

  enum Kind { case folder, file, link }

  /// The kind from the POSIX mode bits an SFTP server reports; nil mode is a file.
  static func kind(permissions: UInt32?) -> Kind {
    switch (permissions ?? 0) & 0o170000 {
    case 0o040000: .folder
    case 0o120000: .link
    default: .file
    }
  }

  /// Folders first, then names without regard to case; "." and ".." never listed.
  static func sorted(_ entries: [SFTPEntry]) -> [SFTPEntry] {
    entries.filter { $0.name != "." && $0.name != ".." }
      .sorted { ($0.isDirectory ? 0 : 1, $0.name.lowercased()) < ($1.isDirectory ? 0 : 1, $1.name.lowercased()) }
  }

  static func join(_ folder: String, _ name: String) -> String { folder.hasSuffix("/") ? folder + name : folder + "/" + name }
}
