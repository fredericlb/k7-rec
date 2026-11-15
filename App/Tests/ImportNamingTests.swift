// Import names its copy by the song's id and writes a uuid into the copy, never into what was picked.
import RehearsalStore
import XCTest
@testable import Rehearsal

@MainActor
final class ImportNamingTests: XCTestCase {
    private func library() throws -> (StoreSongLibrary, URL) {
        let root = try tempFolder()
        return (StoreSongLibrary(store: try Store(), songsFolder: root.appendingPathComponent("Songs")), root)
    }

    private func folder(_ root: URL, parent: String, name: String, chords: String) throws -> URL {
        let dir = root.appendingPathComponent(parent).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try chords.write(to: dir.appendingPathComponent("chords.txt"), atomically: true, encoding: .utf8)
        return dir
    }

    func testAUuidLessFolderGetsItsUuidInTheCopyOnlyAndKeepsItOnReimport() async throws {
        let (lib, root) = try library()
        let source = try folder(root, parent: "A", name: "Intro", chords: "Am")

        _ = await lib.importURLs([source])
        await lib.refresh()
        let id = lib.songs[0].id
        _ = await lib.importURLs([source])
        await lib.refresh()

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent("song.yaml").path), "the source is untouched")
        let copy = root.appendingPathComponent("Songs").appendingPathComponent(lib.songs[0].folder)
        let yaml = try String(contentsOf: copy.appendingPathComponent("song.yaml"), encoding: .utf8)
        XCTAssertTrue(yaml.contains("uuid: \(id)"))
        XCTAssertEqual(lib.songs.count, 1)
        XCTAssertEqual(lib.songs[0].id, id, "the same song again")
        XCTAssertEqual(lib.songs[0].title, "Intro", "the copy's suffix is not the title")
    }

    func testTwoFoldersOfTheSameNameAreTwoSongsAndNeitherCopyIsReplaced() async throws {
        let (lib, root) = try library()
        let a = try folder(root, parent: "A", name: "Intro", chords: "Am")
        let b = try folder(root, parent: "B", name: "Intro", chords: "G")

        _ = await lib.importURLs([a, b])
        await lib.refresh()

        XCTAssertEqual(lib.songs.count, 2)
        XCTAssertEqual(Set(lib.songs.map(\.chords)), ["Am", "G"])
        XCTAssertEqual(Set(lib.songs.map(\.folder)).count, 2)
    }
}
