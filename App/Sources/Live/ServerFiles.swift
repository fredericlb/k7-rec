// The file server seam over RehearsalFTP (FTPS) and RehearsalSFTP: one login per call, so no session outlives a screen.
// What a reader gets wrong: every protocol here is encrypted; a server that offers no TLS or no SSH is refused, never downgraded.
import Foundation
import RehearsalFTP
import RehearsalSFTP

struct ServerFiles: RemoteFiles {
    /// What the two protocols share, as the calls this app makes.
    private struct Open {
        let list: (String) async throws -> [RemoteEntry]
        let download: (String, URL, @escaping @Sendable (Int64) -> Void) async throws -> Void
        let upload: (Data, String) async throws -> Void
        let append: (Data, String) async throws -> Void
        let close: () -> Void
    }

    func hostKey(of account: RemoteAccount) async throws -> String? {
        guard account.kind == .sftp else { return nil }
        let session = try await SFTPSession.open(Self.sftp(account))
        defer { session.close() }
        return session.hostKey
    }

    func list(_ account: RemoteAccount, path: String) async throws -> [RemoteEntry] {
        let session = try await Self.open(account)
        defer { session.close() }
        return try await session.list(path)
    }

    func download(_ account: RemoteAccount, path: String, to url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let session = try await Self.open(account)
        defer { session.close() }
        try await session.download(path, url, progress)
    }

    func append(_ account: RemoteAccount, path: String, text: String, header: String) async throws {
        let session = try await Self.open(account)
        defer { session.close() }
        let parent = (path as NSString).deletingLastPathComponent
        let present = try await session.list(parent.isEmpty ? "/" : parent).contains { $0.name == (path as NSString).lastPathComponent }
        guard present else { return try await session.upload(Data((header + text).utf8), path) }
        // A file that does not end with a line break would run the new line into its last one.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("server-tail-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: copy) }
        try await session.download(path, copy) { _ in }
        let last = (try? Data(contentsOf: copy))?.last
        try await session.append(Data(((last == nil || last == 0x0A ? "" : "\n") + text).utf8), path)
    }

    private static func open(_ a: RemoteAccount) async throws -> Open {
        if a.kind == .sftp {
            let s = try await SFTPSession.open(sftp(a))
            return Open(
                list: { try await s.list($0).map { RemoteEntry(name: $0.name, isFolder: $0.isDirectory, size: $0.size) } },
                download: { try await s.download($0, to: $1, progress: $2) },
                upload: { try await s.upload($0, to: $1) }, append: { try await s.append($0, to: $1) }, close: { s.close() })
        }
        let s = try await FTPSession.open(FTPConfig(
            host: a.host, port: a.port, user: a.user, password: a.password,
            security: a.kind == .ftpsImplicit ? .implicit : .explicit, trustAnyCertificate: a.trustAnyCertificate))
        return Open(
            list: { try await s.list($0).map { RemoteEntry(name: $0.name, isFolder: $0.isDirectory, size: $0.size) } },
            download: { try await s.download($0, to: $1, progress: $2) },
            upload: { try await s.upload($0, to: $1) }, append: { try await s.append($0, to: $1) }, close: { s.close() })
    }

    private static func sftp(_ a: RemoteAccount) -> SFTPConfig {
        SFTPConfig(host: a.host, port: a.port, user: a.user, password: a.password, pinnedKey: a.hostKey)
    }
}
