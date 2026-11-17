// The user's file server (FTPS or SFTP): the form of the settings page, the login test, and the download of picked files.
// What a reader gets wrong: only a login that worked is kept; the password goes to the Keychain, the rest to UserDefaults.
import Foundation
import Observation

@Observable @MainActor
final class ServerAccount {
    var host = ""
    var kind = RemoteProtocol.ftpsExplicit {
        // A port still on the old protocol's default follows the new one.
        didSet { if port == String(oldValue.defaultPort) { port = String(kind.defaultPort) } }
    }
    var port = "21"
    var trustAnyCertificate = false
    var user = ""
    var password = ""
    var folder = "/"
    private(set) var connected: Bool
    /// SFTP: the host key pinned at the first login.
    private(set) var hostKey: String?
    private(set) var busy = false
    private(set) var failure: String?
    /// "Downloading 2 of 5", empty when no download runs.
    private(set) var progress = ""
    @ObservationIgnored let files: RemoteFiles
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: SecretStore
    private static let passwordKey = "server.password"
    private static let keys = ["connected", "host", "port", "user", "folder", "kind", "trust", "hostKey"]

    init(files: RemoteFiles = FakeRemoteFiles(), defaults: UserDefaults = .standard, secrets: SecretStore = MemorySecrets()) {
        (self.files, self.defaults, self.secrets) = (files, defaults, secrets)
        // The keys of the removed plain-FTP login are cleared, so none of its settings or password lingers.
        for key in ["connected", "host", "port", "user", "folder"] { defaults.removeObject(forKey: "ftp." + key) }
        secrets.set(nil, for: "ftp.password")
        connected = defaults.bool(forKey: "server.connected")
        if connected {
            kind = defaults.string(forKey: "server.kind").flatMap(RemoteProtocol.init) ?? .ftpsExplicit
            host = defaults.string(forKey: "server.host") ?? ""
            port = defaults.string(forKey: "server.port") ?? String(kind.defaultPort)
            user = defaults.string(forKey: "server.user") ?? ""
            folder = defaults.string(forKey: "server.folder") ?? "/"
            trustAnyCertificate = defaults.bool(forKey: "server.trust")
            hostKey = defaults.string(forKey: "server.hostKey")
            password = secrets.secret(for: Self.passwordKey) ?? ""
        }
    }

    /// The saved login, nil until one worked.
    var account: RemoteAccount? {
        connected ? RemoteAccount(
            host: host, port: Int(port) ?? kind.defaultPort, user: user, password: password, folder: folder,
            kind: kind, trustAnyCertificate: trustAnyCertificate, hostKey: hostKey) : nil
    }

    /// Logs in and opens the folder; keeps the settings only when both work.
    func connect() async {
        let name = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { failure = "Enter the server's address."; return }
        guard let number = Int(port), (1...65535).contains(number) else { failure = "The port is a number from 1 to 65535."; return }
        var wanted = RemoteAccount(
            host: name, port: number, user: user.isEmpty ? "anonymous" : user, password: password, folder: folder.isEmpty ? "/" : folder,
            kind: kind, trustAnyCertificate: trustAnyCertificate)
        if kind == .sftp, user.trimmingCharacters(in: .whitespaces).isEmpty { failure = "Enter the user name."; return }
        busy = true
        failure = nil
        defer { busy = false }
        do {
            // The first login to an SFTP server pins its key; a later login with another key is refused.
            wanted.hostKey = try await files.hostKey(of: wanted)
            _ = try await files.list(wanted, path: wanted.folder)
            (host, user, folder, hostKey) = (wanted.host, wanted.user, wanted.folder, wanted.hostKey)
            defaults.set(true, forKey: "server.connected")
            defaults.set(wanted.host, forKey: "server.host")
            defaults.set(String(wanted.port), forKey: "server.port")
            defaults.set(wanted.user, forKey: "server.user")
            defaults.set(wanted.folder, forKey: "server.folder")
            defaults.set(wanted.kind.rawValue, forKey: "server.kind")
            defaults.set(wanted.trustAnyCertificate, forKey: "server.trust")
            defaults.set(wanted.hostKey, forKey: "server.hostKey")
            secrets.set(wanted.password, for: Self.passwordKey)
            connected = true
        } catch { failure = error.localizedDescription }
    }

    func disconnect() {
        for key in Self.keys { defaults.removeObject(forKey: "server." + key) }
        secrets.set(nil, for: Self.passwordKey)
        (connected, password, failure, hostKey) = (false, "", nil, nil)
    }

    func list(_ path: String) async throws -> [RemoteEntry] {
        guard let account else { throw URLError(.userAuthenticationRequired) }
        return try await files.list(account, path: path)
    }

    /// Downloads `paths` into a fresh temp folder, in order; on a failure the folder goes and the error is thrown.
    func fetch(_ paths: [String]) async throws -> (urls: [URL], folder: URL) {
        guard let account else { throw URLError(.userAuthenticationRequired) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("server-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { progress = "" }
        do {
            var urls: [URL] = []
            for (i, path) in paths.enumerated() {
                progress = "Downloading \(i + 1) of \(paths.count)"
                // One folder per file, so two songs of the same name never meet.
                let own = folder.appendingPathComponent(String(i), isDirectory: true)
                try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
                let url = own.appendingPathComponent((path as NSString).lastPathComponent)
                try await files.download(account, path: path, to: url, progress: { _ in })
                urls.append(url)
            }
            return (urls, folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// The file at the root of the server where songs the user wants are listed.
    static let missingFile = "/MISSING-SONGS.md"

    /// One markdown list line: "- Artist - Title", on a single line whatever was typed.
    static func missingLine(artist: String, title: String) -> String { "- \(tidy(artist)) - \(tidy(title))\n" }

    /// Words joined by single spaces: a line break or a run of blanks cannot split the list line.
    static func tidy(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    /// Adds a song to `MISSING-SONGS.md` at the root of the server, creating the file when it is not there.
    func addMissingSong(artist: String, title: String) async throws {
        guard let account else { throw URLError(.userAuthenticationRequired) }
        try await files.append(account, path: Self.missingFile, text: Self.missingLine(artist: artist, title: title), header: "# Missing songs\n\n")
    }
}
