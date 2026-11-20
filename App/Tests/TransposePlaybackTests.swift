// A song is heard at its transposition, its instrumental too, a take as recorded; a change is heard at once.
import XCTest
@testable import K7Rec

@MainActor
final class TransposePlaybackTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "tr-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testASongPlaysAtItsTranspositionAndATakeAsRecorded() {
        let player = FakeTakePlayer()
        let model = AppModel(player: player, prefs: SongPrefs(defaults: defaults), stems: FakeStemMaker())
        let url = URL(fileURLWithPath: "/tmp/a.m4a")
        model.setTranspose(3, of: "s1")
        model.togglePlay(id: "song:s1", url: url)
        XCTAssertEqual(player.semitones, 3)
        model.togglePlay(id: "take-1", url: url)
        XCTAssertEqual(player.semitones, 0)
        model.togglePlay(id: "song:s1:instrumental", url: url)
        XCTAssertEqual(player.semitones, 3)
    }

    func testAChangeIsHeardAtOnceOnlyForTheLoadedSong() {
        let player = FakeTakePlayer()
        let model = AppModel(player: player, prefs: SongPrefs(defaults: defaults), stems: FakeStemMaker())
        model.togglePlay(id: "song:s1", url: URL(fileURLWithPath: "/tmp/a.m4a"))
        model.setTranspose(-2, of: "s1")
        XCTAssertEqual(player.semitones, -2)
        model.setTranspose(5, of: "s2")
        XCTAssertEqual(player.semitones, -2, "another song's transposition leaves this one alone")
    }

    func testThePlayIDGivesBackItsSong() {
        XCTAssertEqual(AppModel.songID(inPlayID: "song:ab:instrumental"), "ab")
        XCTAssertEqual(AppModel.songID(inPlayID: "song:ab"), "ab")
        XCTAssertNil(AppModel.songID(inPlayID: "take-1"))
    }
}
