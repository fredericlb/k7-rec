// The capo is kept in the song's row, on frets 0 to 12, and survives a re-import.
import RehearsalStore
import XCTest
@testable import K7Rec

@MainActor
final class CapoTests: XCTestCase {
    func testTheCapoIsWrittenClampedAndKeptByAReimport() async throws {
        let root = try tempFolder()
        let store = try Store()
        let library = StoreSongLibrary(store: store, songsFolder: root.appendingPathComponent("Songs"))
        let wav = root.appendingPathComponent("Jam.wav")
        try makeWav(at: wav, seconds: 1, amp: 0.5)
        _ = await library.importURLs([wav])
        await library.refresh()
        let song = try XCTUnwrap(library.songs.first)

        _ = await library.setCapo(3, for: song)
        let row = try await store.get(RehearsalStore.Song.self, song.id)
        XCTAssertEqual(row?.capo, 3)
        _ = await library.importURLs([wav])
        await library.refresh()
        XCTAssertEqual(library.songs.first { $0.id == song.id }?.capo, 3)

        _ = await library.setCapo(15, for: song)
        XCTAssertEqual(library.songs.first { $0.id == song.id }?.capo, 12)
    }

    func testTheModelSetsTheCapo() async {
        let library = FakeSongLibrary()
        let model = AppModel(library: library)
        await model.setCapo(2, of: library.songs[0])
        XCTAssertEqual(library.songs[0].capo, 2)
        await model.setCapo(0, of: library.songs[0])
        XCTAssertEqual(library.songs[0].capo, 0)
    }
}
