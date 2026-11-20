// Looks a song up on lrclib.net, which answers with plain and timed lyrics and needs no key (docs/app.md).
// What a reader gets wrong: only the title, the artist and the duration leave the device, and only on a download.
import AVFoundation
import Foundation

struct LRCLibClient: LyricsFetching {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    let transport: Transport
    let base = URL(string: "https://lrclib.net/api")!

    init(transport: @escaping Transport = Self.live) { self.transport = transport }

    static let live: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    func find(title: String, artist: String, audio: URL?) async throws -> FoundLyrics? {
        if let seconds = await Self.duration(of: audio), !artist.isEmpty,
           let exact = try await get("get", ["track_name": title, "artist_name": artist, "duration": String(Int(seconds.rounded()))]) {
            return Self.found(try JSONDecoder().decode(Entry.self, from: exact))
        }
        var query = ["track_name": title]
        if !artist.isEmpty { query["artist_name"] = artist }
        guard let data = try await get("search", query) else { return nil }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        return (entries.first { $0.syncedLyrics?.isEmpty == false } ?? entries.first { $0.plainLyrics?.isEmpty == false }).flatMap(Self.found)
    }

    /// The body of a 200, nil for a 404, a thrown error for anything else.
    private func get(_ path: String, _ query: [String: String]) async throws -> Data? {
        var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: parts.url!, timeoutInterval: 15)
        request.setValue("K7 REC (iOS app)", forHTTPHeaderField: "User-Agent")
        let (data, http) = try await transport(request)
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    struct Entry: Decodable {
        var plainLyrics: String?
        var syncedLyrics: String?
        var instrumental: Bool?
    }

    static func found(_ e: Entry) -> FoundLyrics? {
        let synced = e.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = e.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if e.instrumental == true || (plain.isEmpty && (synced ?? "").isEmpty) { return nil }
        return FoundLyrics(plain: plain.isEmpty ? Self.words(of: synced ?? "") : plain, synced: synced?.isEmpty == false ? synced : nil)
    }

    /// The words of an LRC text: its lines without their `[mm:ss.xx]` tags.
    static func words(of lrc: String) -> String {
        lrc.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: #"^\s*(\[[^\]]*\])+\s*"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
    }

    static func duration(of url: URL?) async -> Double? {
        guard let url, let t = try? await AVURLAsset(url: url).load(.duration), t.isNumeric, t.seconds > 0 else { return nil }
        return t.seconds
    }
}
