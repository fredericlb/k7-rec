// What the live stem maker decides without a model: where the stems live, what it says when none is installed.
import RehearsalStems
import XCTest
@testable import K7Rec

@MainActor
final class StemMakerTests: XCTestCase {
    private func setup() throws -> (maker: LiveStemMaker, root: URL, song: Song) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stemmaker-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Songs/Jam abcd1234", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let maker = LiveStemMaker(songs: root.appendingPathComponent("Songs"), models: root.appendingPathComponent("Models"), bundle: Bundle(for: StemMakerTests.self))
        var song = Song(id: "1", title: "Jam", artist: "")
        (song.folder, song.audioURL) = ("Jam abcd1234", folder.appendingPathComponent("original.m4a"))
        return (maker, root, song)
    }

    func testWithoutAModelItSaysSoAndWritesNothing() async throws {
        let (maker, root, song) = try setup()
        XCTAssertFalse(maker.hasModel)
        let failure = await maker.separate(song) { _ in }
        XCTAssertTrue(try XCTUnwrap(failure).contains("Models folder"))
        XCTAssertNil(maker.existing(for: song))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Songs/Jam abcd1234/stems").path))
    }

    func testAModelDroppedInTheModelsFolderIsSeen() throws {
        let (maker, root, _) = try setup()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Models/StemSeparator.mlpackage"), withIntermediateDirectories: true)
        XCTAssertTrue(maker.hasModel)
    }

    func testStemsInTheSongFolderAreFoundAndRemoved() throws {
        let (maker, root, song) = try setup()
        let stems = root.appendingPathComponent("Songs/Jam abcd1234/stems", isDirectory: true)
        try FileManager.default.createDirectory(at: stems, withIntermediateDirectories: true)
        for s in Stem.allCases { try Data().write(to: stems.appendingPathComponent(s.fileName)) }
        XCTAssertEqual(maker.existing(for: song)?.count, 4)
        maker.remove(for: song)
        XCTAssertNil(maker.existing(for: song))
    }
}
