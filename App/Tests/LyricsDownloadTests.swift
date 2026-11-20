import XCTest
@testable import K7Rec

@MainActor
final class LyricsDownloadTests: XCTestCase {
    private let timed = "[00:04.00]First line\n[00:09.00]Second line"

    private func answer(_ code: Int, _ body: String) -> LRCLibClient.Transport {
        { request in (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!) }
    }

    func testTheExactLookupIsUsedWhenTheDurationIsKnownElseTheSearch() async throws {
        let seen = Seen()
        let client = LRCLibClient { request in
            seen.add(request.url!.path)
            return (Data(#"[{"plainLyrics":"a","syncedLyrics":null}]"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let found = try await client.find(title: "Blue", artist: "Band", audio: nil)
        XCTAssertEqual(found, FoundLyrics(plain: "a", synced: nil))
        XCTAssertEqual(seen.paths, ["/api/search"])
    }

    func testANotFoundIsNilAndAServerErrorThrows() async throws {
        let none = try await LRCLibClient(transport: answer(404, "{}")).find(title: "x", artist: "", audio: nil)
        XCTAssertNil(none)
        do { _ = try await LRCLibClient(transport: answer(500, "")).find(title: "x", artist: "", audio: nil); XCTFail("expected a throw") } catch {}
    }

    func testAnInstrumentalHasNoLyrics() {
        XCTAssertNil(LRCLibClient.found(.init(plainLyrics: "", syncedLyrics: "", instrumental: true)))
    }

    func testTheWordsOfATimedTextOnlyLoseTheirTags() {
        XCTAssertEqual(LRCLibClient.words(of: timed), "First line\nSecond line")
    }

    func testNewLyricsAreSavedTimedWhenTheServiceHasTiming() async {
        let library = FakeSongLibrary()
        let model = AppModel(library: library, lyrics: FakeLyricsFetcher(result: FoundLyrics(plain: "First line\nSecond line", synced: timed)))
        await model.downloadLyrics(for: library.songs[2])
        XCTAssertTrue(library.songs[2].lyrics.contains("{{00:04.00}}"), library.songs[2].lyrics)
    }

    func testAFailureSaysSoAndLeavesTheSongAlone() async {
        let library = FakeSongLibrary()
        let model = AppModel(library: library, lyrics: FakeLyricsFetcher(fails: true))
        await model.downloadLyrics(for: library.songs[2])
        XCTAssertEqual(model.notice, "LRCLIB could not be reached.")
        XCTAssertEqual(library.songs[2].lyrics, "")
    }

    func testExistingWordsAreNeverReplacedOnlyTimed() async {
        let library = FakeSongLibrary()
        let model = AppModel(library: library, lyrics: FakeLyricsFetcher(result: FoundLyrics(plain: "Other words", synced: nil)))
        let before = library.songs[1].lyrics
        await model.downloadLyrics(for: library.songs[1])
        XCTAssertEqual(library.songs[1].lyrics, before)
        XCTAssertEqual(model.notice, "LRCLIB has no timing that fits the lyrics of Slow Waltz.")
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    func add(_ p: String) { lock.lock(); all.append(p); lock.unlock() }
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return all }
}
