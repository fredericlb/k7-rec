// Import into a temp store: a song folder keeps its texts and is idempotent, an audio file is a song alone.
import RehearsalStore
import XCTest
@testable import Rehearsal

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

    func testAFolderWithNothingInItFailsAndLeavesNoSong() async throws {
        let (lib, _, root) = try library()
        let empty = root.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let failure = await lib.importURLs([empty])

        XCTAssertNotNil(failure)
        XCTAssertTrue(lib.songs.isEmpty)
    }
}
