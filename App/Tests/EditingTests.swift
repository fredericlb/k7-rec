// Editing a song folder: texts rewrite their file and row, an emptied text removes both, sheets and tags.
import RehearsalStore
import XCTest
@testable import K7Rec

@MainActor
final class EditingTests: XCTestCase {
    private func imported() async throws -> (StoreSongLibrary, Store, URL, URL) {
        let root = try tempFolder()
        let store = try Store()
        let lib = StoreSongLibrary(store: store, songsFolder: root.appendingPathComponent("Songs"))
        let folder = root.appendingPathComponent("Blue", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "Am F\n".write(to: folder.appendingPathComponent("chords.txt"), atomically: true, encoding: .utf8)
        try "uuid: 11111111-2222-3333-4444-555555555555\ntitle: Blue\n".write(to: folder.appendingPathComponent("song.yaml"), atomically: true, encoding: .utf8)
        let failure = await lib.importURLs([folder])
        XCTAssertNil(failure)
        for _ in 0..<100 where lib.songs.isEmpty || !lib.songs[0].hasChords { try? await Task.sleep(nanoseconds: 20_000_000) }
        return (lib, store, root, root.appendingPathComponent("Songs/Blue 11111111"))
    }

    func testSavingATextRewritesTheFileAndTheRow() async throws {
        let (lib, store, _, dir) = try await imported()
        let failure = await lib.saveText(.lyrics, "{{00:01}} Hello", for: lib.songs[0])
        XCTAssertNil(failure)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("lyrics.txt"), encoding: .utf8), "{{00:01}} Hello")
        XCTAssertEqual(lib.songs[0].lyrics, "{{00:01}} Hello")
        XCTAssertTrue(lib.songs[0].hasLyrics)
        let rows = try await store.list(Query<SongFile>())
        XCTAssertEqual(rows.filter { $0.kind == .lyrics }.map(\.path), ["Blue 11111111/lyrics.txt"])
        _ = await lib.saveText(.lyrics, "again", for: lib.songs[0])
        let after = try await store.list(Query<SongFile>())
        XCTAssertEqual(after.filter { $0.kind == .lyrics }.count, 1)
    }

    func testAnEmptiedTextRemovesItsFileAndRow() async throws {
        let (lib, store, _, dir) = try await imported()
        _ = await lib.saveText(.chords, "  \n", for: lib.songs[0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("chords.txt").path))
        XCTAssertFalse(lib.songs[0].hasChords)
        let rows = try await store.list(Query<SongFile>())
        XCTAssertTrue(rows.isEmpty)
    }

    func testSavingLyricsRetimesTimedChords() async throws {
        let (lib, _, _, _) = try await imported()
        _ = await lib.saveText(.chords, "Am\n{{00:01.00}} Hello world", for: lib.songs[0])
        let failure = await lib.saveLyrics("{{00:05.00}} Hello world", for: lib.songs[0])
        XCTAssertNil(failure)
        XCTAssertEqual(lib.songs[0].chords, "Am\n{{00:05.00}} Hello world")
    }

    func testAddingChordsTimesThemFromTheLyrics() async throws {
        let (lib, _, _, _) = try await imported()
        _ = await lib.saveText(.lyrics, "{{00:05.00}} Hello world", for: lib.songs[0])
        let failure = await lib.saveChords("Am\nHello world", for: lib.songs[0])
        XCTAssertNil(failure)
        XCTAssertEqual(lib.songs[0].chords, "Am\n{{00:05.00}} Hello world")
    }

    func testSavingLyricsTimesChordsThatHadNoTimeYet() async throws {
        let (lib, _, _, _) = try await imported()
        _ = await lib.saveText(.chords, "Am\nHello world", for: lib.songs[0])
        _ = await lib.saveLyrics("{{00:05.00}} Hello world", for: lib.songs[0])
        XCTAssertEqual(lib.songs[0].chords, "Am\n{{00:05.00}} Hello world")
    }

    func testChordsStayAsTypedWhenTheLyricsAreNotTimed() async throws {
        let (lib, _, _, _) = try await imported()
        _ = await lib.saveText(.lyrics, "Hello world", for: lib.songs[0])
        _ = await lib.saveChords("Am\nHello world", for: lib.songs[0])
        XCTAssertEqual(lib.songs[0].chords, "Am\nHello world")
    }

    func testASheetIsCopiedInTheOrderAddedAndRemoved() async throws {
        let (lib, _, root, dir) = try await imported()
        let pdf = root.appendingPathComponent("score.pdf")
        try Data("%PDF".utf8).write(to: pdf)
        _ = await lib.addSheet(from: pdf, to: lib.songs[0])
        _ = await lib.addSheet(from: pdf, to: lib.songs[0])
        XCTAssertEqual(lib.songs[0].sheets.map(\.name), ["score.pdf", "score 2.pdf"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("sheets/score 2.pdf").path))
        let first = lib.songs[0].sheets[0]
        _ = await lib.removeSheet(first, from: lib.songs[0])
        XCTAssertEqual(lib.songs[0].sheets.map(\.name), ["score 2.pdf"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
    }

    func testTagsAreKeptOnTheSongRow() async throws {
        let (lib, store, _, _) = try await imported()
        _ = await lib.setTags(["rock", "slow"], for: lib.songs[0])
        let rows = try await store.list(Query<RehearsalStore.Song>())
        XCTAssertEqual(rows[0].tags, ["rock", "slow"])
    }
}
