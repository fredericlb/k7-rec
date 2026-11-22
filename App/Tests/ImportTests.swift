// Import into a temp store: a song folder keeps its texts and is idempotent, an audio file is a song alone.
import RehearsalStore
import XCTest
@testable import K7Rec

@MainActor
final class ImportTests: XCTestCase {
    private func library() throws -> (StoreSongLibrary, Store, URL) {
        let root = try tempFolder()
        let store = try Store()
        return (StoreSongLibrary(store: store, songsFolder: root.appendingPathComponent("Songs")), store, root)
    }

    private func settle(_ library: StoreSongLibrary, until check: () -> Bool) async {
        for _ in 0..<100 where !check() { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    func testSongFolderImportsOnceWithItsTexts() async throws {
        let (lib, store, root) = try library()
        let folder = root.appendingPathComponent("Blue Monday", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "uuid: 11111111-2222-3333-4444-555555555555\ntitle: Blue Monday\nartist: New Order\n".write(to: folder.appendingPathComponent("song.yaml"), atomically: true, encoding: .utf8)
        try "Am F\n".write(to: folder.appendingPathComponent("chords.txt"), atomically: true, encoding: .utf8)
        try makeWav(at: folder.appendingPathComponent("original.wav"), seconds: 1, amp: 0.5)

        for _ in 0..<2 { let failure = await lib.importURLs([folder]); XCTAssertNil(failure) }
        await settle(lib) { lib.songs.first?.audioURL != nil }

        XCTAssertEqual(lib.songs.count, 1)
        XCTAssertEqual(lib.songs[0].title, "Blue Monday")
        XCTAssertEqual(lib.songs[0].artist, "New Order")
        XCTAssertEqual(lib.songs[0].chords, "Am F\n")
        XCTAssertTrue(lib.songs[0].hasChords && !lib.songs[0].hasLyrics)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.songs[0].audioURL!.path))
        let files = try await store.list(Query<SongFile>())
        XCTAssertEqual(files.count, 2)
    }

    func testAudioFileAloneBecomesASongNamedByItsFilename() async throws {
        let (lib, _, root) = try library()
        let wav = root.appendingPathComponent("Slow Waltz.wav")
        try makeWav(at: wav, seconds: 1, amp: 0.5)

        let failure = await lib.importURLs([wav])
        await settle(lib) { lib.songs.first?.audioURL != nil }

        XCTAssertNil(failure)
        XCTAssertEqual(lib.songs.map(\.title), ["Slow Waltz"])
        let wave = await lib.wave(of: lib.songs[0])
        XCTAssertEqual(wave.duration, 1, accuracy: 0.05)
        XCTAssertFalse(wave.samples.isEmpty)
    }

    func testAFlacIsNamedByItsVorbisComments() async throws {
        let root = try tempFolder()
        let flac = root.appendingPathComponent("01 track.flac")
        try makeTaggedFlac(at: flac, comments: ["title=One More Time", "ARTIST=Daft Punk"])

        let (title, artist) = await SongImporter.tags(of: flac, fallback: "01 track")

        XCTAssertEqual(title, "One More Time")
        XCTAssertEqual(artist, "Daft Punk")
    }

    func testAFolderWithNothingInItFailsAndLeavesNoSong() async throws {
        let (lib, _, root) = try library()
        let empty = root.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let failure = await lib.importURLs([empty])

        XCTAssertNotNil(failure)
        XCTAssertTrue(lib.songs.isEmpty)
    }

    private func wavSong(_ root: URL, _ name: String = "Intro") throws -> URL {
        let wav = root.appendingPathComponent("\(name).wav")
        try makeWav(at: wav, seconds: 1, amp: 0.5)
        return wav
    }

    func testAReimportKeepsWhatWasMadeInTheApp() async throws {
        let (lib, _, root) = try library()
        let wav = try wavSong(root)
        _ = await lib.importURLs([wav])
        await lib.refresh()
        let song = lib.songs[0]
        let sheet = root.appendingPathComponent("score.pdf")
        try Data("pdf".utf8).write(to: sheet)
        _ = await lib.saveText(.lyrics, "la la", for: song)
        _ = await lib.addSheet(from: sheet, to: lib.songs[0])
        _ = await lib.setInfo(title: lib.songs[0].title, artist: lib.songs[0].artist, tags: ["x"], for: lib.songs[0])

        let failure = await lib.importURLs([wav])
        await lib.refresh()

        XCTAssertNil(failure)
        XCTAssertEqual(lib.songs.count, 1)
        XCTAssertEqual(lib.songs[0].lyrics, "la la")
        XCTAssertEqual(lib.songs[0].sheets.map(\.name), ["score.pdf"])
        XCTAssertEqual(lib.songs[0].tags, ["x"])
        XCTAssertNotNil(lib.songs[0].audioURL)
    }

    func testACopyThatFailsKeepsTheOldSong() async throws {
        let (lib, _, root) = try library()
        let wav = try wavSong(root)
        _ = await lib.importURLs([wav])
        await lib.refresh()
        _ = await lib.saveText(.lyrics, "keep me", for: lib.songs[0])
        let before = lib.songs[0]
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: wav.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: wav.path) }

        let failure = await lib.importURLs([wav])
        await lib.refresh()

        XCTAssertNotNil(failure)
        XCTAssertEqual(lib.songs.count, 1)
        XCTAssertEqual(lib.songs[0].lyrics, "keep me")
        XCTAssertTrue(FileManager.default.fileExists(atPath: before.audioURL!.path))
        let left = try FileManager.default.contentsOfDirectory(atPath: lib.root.path)
        XCTAssertFalse(left.contains { $0.hasPrefix(".importing") })
    }

    func testStampingKeepsAYamlThatStartsWithADocumentMarkerOneDocument() throws {
        let dir = try tempFolder()
        try "---\ntitle: T\nartist: X\ntags: [rock]\n".write(to: dir.appendingPathComponent("song.yaml"), atomically: true, encoding: .utf8)
        try "Am".write(to: dir.appendingPathComponent("chords.txt"), atomically: true, encoding: .utf8)

        try SongImporter.stamp(uuid: "aaaaaaaa-0000-0000-0000-000000000000", in: dir)
        let (song, _) = try SongFolder.read(dir)

        XCTAssertEqual(song.uuid, "aaaaaaaa-0000-0000-0000-000000000000")
        XCTAssertEqual(song.title, "T")
        XCTAssertEqual(song.artist, "X")
        XCTAssertEqual(song.tags, ["rock"])
    }

    func testATextTypedAfterEmptyingTheLastFileGoesBackToTheSongsOwnFolder() async throws {
        let (lib, _, root) = try library()
        for name in ["A", "B"] {
            let folder = root.appendingPathComponent(name).appendingPathComponent("Intro", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "words \(name)".write(to: folder.appendingPathComponent("lyrics.txt"), atomically: true, encoding: .utf8)
            _ = await lib.importURLs([folder])
        }
        await lib.refresh()
        XCTAssertEqual(lib.songs.count, 2)
        let (one, two) = (lib.songs[0], lib.songs[1])
        for song in [one, two] { _ = await lib.saveText(.lyrics, "", for: lib.songs.first { $0.id == song.id }!) }
        for song in [one, two] { _ = await lib.saveText(.lyrics, "new \(song.id)", for: lib.songs.first { $0.id == song.id }!) }

        XCTAssertEqual(lib.songs.map(\.lyrics).sorted(), ["new \(one.id)", "new \(two.id)"].sorted())
        XCTAssertNotEqual(lib.songs[0].folder, lib.songs[1].folder)
        XCTAssertTrue(lib.songs.allSatisfy { $0.folder.hasPrefix("Intro ") })
    }
}

extension ImportTests {
    func testAWaveIsDecodedOncePerFileVersion() async throws {
        let (lib, _, root) = try library()
        let wav = root.appendingPathComponent("Loop.wav")
        try makeWav(at: wav, seconds: 1, amp: 0.5)
        _ = await lib.importURLs([wav])
        await lib.refresh()
        let song = lib.songs[0]
        let url = song.audioURL!
        let stamp = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        let first = await lib.wave(of: song)
        try makeWav(at: url, seconds: 2, amp: 0.5)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)

        let cached = await lib.wave(of: song)
        try FileManager.default.setAttributes([.modificationDate: stamp.addingTimeInterval(5)], ofItemAtPath: url.path)
        let fresh = await lib.wave(of: song)

        XCTAssertEqual(first.duration, 1, accuracy: 0.05)
        XCTAssertEqual(cached, first, "served from the cache while the file's date is the same")
        XCTAssertEqual(fresh.duration, 2, accuracy: 0.05)
    }
}
