import XCTest
@testable import K7Rec

@MainActor
final class VersionSwitchTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "ver-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func setup(stems: Bool) -> (AppModel, FakeStemMaker, FakeTakePlayer, Song) {
        let maker = FakeStemMaker()
        let player = FakeTakePlayer()
        var song = FakeSongLibrary().songs[0]
        song.audioURL = URL(fileURLWithPath: "/tmp/full.m4a")
        if stems { maker.made.insert(song.id) }
        let model = AppModel(player: player, prefs: SongPrefs(defaults: defaults), stems: maker)
        return (model, maker, player, song)
    }

    func testTheInstrumentalIsMixedOnceAndThePositionAndPlayingCarryOver() async {
        let (model, maker, player, song) = setup(stems: true)
        model.togglePlay(id: model.playID(of: song), url: song.audioURL!)
        player.seek(to: 12)
        XCTAssertTrue(player.isPlaying)
        await model.switchVersion(of: song)
        XCTAssertTrue(model.playsInstrumental(song))
        XCTAssertEqual(player.loadedID, "song:1:instrumental")
        XCTAssertEqual(player.position, 12)
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(maker.instrumental.contains("1"))
        await model.switchVersion(of: song)
        XCTAssertFalse(model.playsInstrumental(song))
        XCTAssertEqual(player.loadedID, "song:1")
        XCTAssertEqual(player.position, 12)
        XCTAssertEqual(model.playURL(of: song), song.audioURL)
    }

    func testTheChoiceIsKeptPerSong() async {
        let (model, _, _, song) = setup(stems: true)
        await model.switchVersion(of: song)
        XCTAssertTrue(SongPrefs(defaults: defaults).isInstrumental(song.id))
    }

    func testWithoutStemsNothingSwitchesAndTheReasonIsShown() async {
        let (model, _, _, song) = setup(stems: false)
        await model.switchVersion(of: song)
        XCTAssertFalse(model.playsInstrumental(song))
        XCTAssertEqual(model.notice, "No stems.")
        XCTAssertFalse(model.prefs.isInstrumental(song.id))
    }

    func testRemovedStemsPlayTheFullSongAgainWhateverWasChosen() async {
        let (model, maker, _, song) = setup(stems: true)
        await model.switchVersion(of: song)
        maker.remove(for: song)
        XCTAssertFalse(model.playsInstrumental(song))
        XCTAssertEqual(model.playURL(of: song), song.audioURL)
    }
}
