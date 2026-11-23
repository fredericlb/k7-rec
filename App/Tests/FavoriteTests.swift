// A favourite is kept in the song's row, survives a re-import, and is listed before the other songs.
import RehearsalStore
import XCTest
@testable import K7Rec

@MainActor
final class FavoriteTests: XCTestCase {
    func testFavouritesComeFirstAndKeepTheirOrder() {
        let songs = ["a", "b", "c", "d"].map { K7Rec.Song(id: $0, title: $0, artist: "", favorite: $0 == "b" || $0 == "d") }
        XCTAssertEqual(songs.favoritesFirst.map(\.id), ["b", "d", "a", "c"])
    }

    func testAFavouriteIsWrittenToTheRowAndSurvivesAReimport() async throws {
        let root = try tempFolder()
        let store = try Store()
        let library = StoreSongLibrary(store: store, songsFolder: root.appendingPathComponent("Songs"))
        let wav = root.appendingPathComponent("Jam.wav")
        try makeWav(at: wav, seconds: 1, amp: 0.5)
        _ = await library.importURLs([wav])
        await library.refresh()
        let song = try XCTUnwrap(library.songs.first)

        let failure = await library.setFavorite(true, for: song)
        XCTAssertNil(failure)
        let row = try await store.get(RehearsalStore.Song.self, song.id)
        XCTAssertEqual(row?.favorite, true)

        _ = await library.importURLs([wav])
        await library.refresh()
        XCTAssertEqual(library.songs.first { $0.id == song.id }?.favorite, true)
    }

    func testTheModelTogglesAFavourite() async {
        let library = FakeSongLibrary()
        let model = AppModel(library: library)
        let song = library.songs[2]

        await model.toggleFavorite(song)
        XCTAssertEqual(library.songs.favoritesFirst.first?.id, song.id)
        await model.toggleFavorite(library.songs[2])
        XCTAssertEqual(library.songs[2].favorite, false)
    }
}
