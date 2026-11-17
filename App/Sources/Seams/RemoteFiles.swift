// What the server settings and the import sheet need from a file server; the real one is Live/ServerFiles.
import Foundation

/// How a server is spoken to; none of them sends a password in the clear.
enum RemoteProtocol: String, CaseIterable, Identifiable, Sendable {
    case ftpsExplicit, ftpsImplicit, sftp

    var id: String { rawValue }
    var label: String {
        switch self {
        case .ftpsExplicit: "FTPS (explicit TLS)"
        case .ftpsImplicit: "FTPS (implicit TLS)"
        case .sftp: "SFTP (SSH)"
        }
    }
    var defaultPort: Int {
        switch self {
        case .ftpsExplicit: 21
        case .ftpsImplicit: 990
        case .sftp: 22
        }
    }
}

struct RemoteAccount: Sendable, Equatable {
    var host: String
    var port: Int = 21
    var user: String = "anonymous"
    var password: String = ""
    /// The folder the import sheet opens on.
    var folder: String = "/"
    var kind: RemoteProtocol = .ftpsExplicit
    /// FTPS only: accepts a certificate the system does not trust, such as a self-signed one.
    var trustAnyCertificate = false
    /// SFTP only: the fingerprint of the host key seen at the first login; a different one is refused.
    var hostKey: String?
}

struct RemoteEntry: Identifiable, Hashable, Sendable {
    var name: String
    var isFolder: Bool
    var size: Int64?
    var id: String { name }

    /// Whether the importer takes this file: the audio formats a song folder's master may have.
    var isAudio: Bool {
        !isFolder && ["flac", "wav", "mp3", "m4a", "aac", "aif", "aiff", "ogg", "opus"].contains((name as NSString).pathExtension.lowercased())
    }
}

protocol RemoteFiles: Sendable {
    /// The fingerprint of the key an SFTP server shows, for the account to pin; nil for FTPS, which has none to pin.
    func hostKey(of account: RemoteAccount) async throws -> String?
    func list(_ account: RemoteAccount, path: String) async throws -> [RemoteEntry]
    /// Streams one file to `url`; `progress` gets the bytes so far.
    func download(_ account: RemoteAccount, path: String, to url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws
    /// Puts `text` at the end of the file, on a line of its own; a file that is not there is created, starting with `header`.
    func append(_ account: RemoteAccount, path: String, text: String, header: String) async throws
}

/// A server of two folders and three songs, and one that fails when `fails`.
struct FakeRemoteFiles: RemoteFiles {
    var fails = false
    /// What was appended, as (path, text), for a test to read.
    let appended = AppendLog()
    var tree: [String: [RemoteEntry]] = [
        "/": [RemoteEntry(name: "Live", isFolder: true), RemoteEntry(name: "intro.mp3", isFolder: false, size: 4), RemoteEntry(name: "notes.txt", isFolder: false, size: 2)],
        "/Live": [RemoteEntry(name: "jam.flac", isFolder: false, size: 4)],
    ]

    func hostKey(of account: RemoteAccount) async throws -> String? {
        if fails { throw URLError(.cannotConnectToHost) }
        return account.kind == .sftp ? "SHA256:fake" : nil
    }

    func list(_ account: RemoteAccount, path: String) async throws -> [RemoteEntry] {
        if fails { throw URLError(.cannotConnectToHost) }
        guard let entries = tree[path] else { throw URLError(.fileDoesNotExist) }
        return entries
    }

    func download(_ account: RemoteAccount, path: String, to url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        if fails { throw URLError(.cannotConnectToHost) }
        try Data("data".utf8).write(to: url)
        progress(4)
    }

    func append(_ account: RemoteAccount, path: String, text: String, header: String) async throws {
        if fails { throw URLError(.cannotConnectToHost) }
        appended.add(path, text)
    }
}

final class AppendLog: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [(path: String, text: String)] = []
    func add(_ path: String, _ text: String) { lock.lock(); all.append((path, text)); lock.unlock() }
    var entries: [(path: String, text: String)] { lock.lock(); defer { lock.unlock() }; return all }
}
