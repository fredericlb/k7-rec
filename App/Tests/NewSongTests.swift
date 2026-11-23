// A song made without audio: its folder holds only its sidecar, nothing plays, and no lyrics are looked up.
import RehearsalStore
import XCTest
@testable import K7Rec

@MainActor
final class NewSongTests: XCTestCase {
    func testANewSongIsAFolderWithItsSidecarAndNoAudio() async throws {
        let root = try tempFolder().appendingPathComponent("Songs")
        let library = StoreSongLibrary(store: try Store(), songsFolder: root)

        let id = try await library.createSong(title: "Draft: Waltz", artist: "Us").get()

        let song = try XCTUnwrap(library.songs.first { $0.id == id })
        XCTAssertEqual(song.title, "Draft: Waltz")
        XCTAssertEqual(song.artist, "Us")
        XCTAssertNil(song.audioURL)
        let folder = root.appendingPathComponent(song.folder)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["song.yaml"])
        XCTAssertEqual(try SongFolder.read(folder).song.id, id)
        let wave = await library.wave(of: song)
        XCTAssertTrue(wave.samples.isEmpty)
    }

    func testANewSongTakesItsTextsInItsOwnFolder() async throws {
        let root = try tempFolder().appendingPathComponent("Songs")
        let library = StoreSongLibrary(store: try Store(), songsFolder: root)
        let id = try await library.createSong(title: "Riff", artist: "").get()
        let song = try XCTUnwrap(library.songs.first { $0.id == id })

        let failure = await library.saveText(.chords, "Am F C G", for: song)

        XCTAssertNil(failure)
        XCTAssertEqual(library.songs.first { $0.id == id }?.chords, "Am F C G")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(song.folder).appendingPathComponent("chords.txt").path))
    }

    func testCreatingOpensTheSongAndLooksNoLyricsUp() async {
        let library = FakeSongLibrary()
        let model = AppModel(library: library, lyrics: FakeLyricsFetcher(result: FoundLyrics(plain: "words", synced: nil)))

        await model.createSong(title: "  Ballad ", artist: "Trio")

        let song = library.songs.first { $0.title == "Ballad" }
        XCTAssertNotNil(song)
        XCTAssertEqual(model.sharedSong, song?.id)
        XCTAssertEqual(song?.hasLyrics, false)
        XCTAssertNil(model.notice)
    }

    func testABlankTitleMakesNoSong() async {
        let library = FakeSongLibrary()
        let model = AppModel(library: library)
        let before = library.songs.count

        await model.createSong(title: "  ", artist: "Trio")

        XCTAssertEqual(library.songs.count, before)
        XCTAssertEqual(model.notice, "Enter a title.")
    }
}
