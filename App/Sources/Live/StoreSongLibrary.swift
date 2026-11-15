// The Songs list over the store: it observes songs and their files and maps them to the app's Song.
// What a reader gets wrong: texts are read from the copied folder at mapping time, not stored in rows.
import Foundation
import Observation
import RehearsalAudio
import RehearsalStore

@Observable @MainActor
final class StoreSongLibrary: SongLibrary {
    private(set) var songs: [Song] = []
    @ObservationIgnored private let importer: SongImporter
    @ObservationIgnored let root: URL
    @ObservationIgnored let store: Store
    @ObservationIgnored var rows: [RehearsalStore.Song] = [] { didSet { generation += 1 } }
    @ObservationIgnored var files: [SongFile] = [] { didSet { generation += 1 } }
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(store: Store, songsFolder: URL) {
        importer = SongImporter(store: store, songs: songsFolder)
        root = songsFolder
        self.store = store
        // A crash mid-import leaves its temp folder; nothing else lives under that prefix.
        for name in (try? FileManager.default.contentsOfDirectory(atPath: songsFolder.path)) ?? [] where name.hasPrefix(".importing-") {
            try? FileManager.default.removeItem(at: songsFolder.appendingPathComponent(name))
        }
        tasks.append(Task { [weak self] in
            do { for try await v in store.observe(Query<RehearsalStore.Song>(orderBy: "createdAt", descending: true)) { self?.rows = v; await self?.remap() } } catch {}
        })
        tasks.append(Task { [weak self] in
            do { for try await v in store.observe(Query<SongFile>(orderBy: "position")) { self?.files = v; await self?.remap() } } catch {}
        })
    }

    deinit { tasks.forEach { $0.cancel() } }

    func importURLs(_ urls: [URL]) async -> String? {
        let failures = await importer.importURLs(urls)
        return failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    func wave(of song: Song) async -> Wave {
        guard let url = song.audioURL else { return Wave(samples: [], duration: 0) }
        let read = await Task.detached { try? EnvelopeReader.read(url: url) }.value
        guard let read else { return Wave(samples: [], duration: 0) }
        return Wave(samples: read.envelope.scaled(by: Gain.envelope(rawPeak: read.envelope.peak)).samples, duration: read.durationSec)
    }

    /// Reads both collections again, so a caller sees its own write before the observation delivers it.
    func refresh() async {
        if let r = try? await store.list(Query<RehearsalStore.Song>(orderBy: "createdAt", descending: true)) { rows = r }
        if let f = try? await store.list(Query<SongFile>(orderBy: "position")) { files = f }
        await remap()
    }

    /// Builds the songs off the main actor and assigns them once the rows and files stopped changing meanwhile.
    func remap() async {
        while true {
            let (mine, rows, files, root) = (generation, rows, files, root)
            let built = await Task.detached { Self.build(rows, files, root) }.value
            if mine == generation { songs = built; return }
        }
    }

    nonisolated static func build(_ rows: [RehearsalStore.Song], _ files: [SongFile], _ root: URL) -> [Song] {
        let bysong = Dictionary(grouping: files, by: \.songId)
        return rows.map { row in
            let own = bysong[row.id] ?? []
            func text(_ kind: SongFileKind) -> String? {
                own.first { $0.kind == kind }.flatMap { try? String(contentsOf: root.appendingPathComponent($0.path), encoding: .utf8) }
            }
            let chords = text(.chords), lyrics = text(.lyrics), tab = text(.tabs)
            return Song(
                id: row.id, title: row.title, artist: row.artist, hasChords: chords != nil, hasLyrics: lyrics != nil,
                hasTab: tab != nil, hasSheets: own.contains { $0.kind == .sheet },
                hasDiagrams: !SongText.diagramChords(chords: chords ?? "", lyrics: lyrics ?? "", semitones: 0).isEmpty,
                chords: chords ?? "", lyrics: lyrics ?? "", tab: tab ?? "", tags: row.tags,
                sheets: own.filter { $0.kind == .sheet }.map { SongSheet(id: $0.id, name: $0.name, url: root.appendingPathComponent($0.path)) },
                folder: row.folder.isEmpty ? own.first.map { String($0.path.prefix { $0 != "/" }) } ?? "" : row.folder,
                added: Date(timeIntervalSince1970: row.createdAt),
                audioURL: own.first { $0.kind == .audio }.map { root.appendingPathComponent($0.path) },
                referenceID: row.source == .appleMusicReference ? row.storeId : "")
        }
    }
}
