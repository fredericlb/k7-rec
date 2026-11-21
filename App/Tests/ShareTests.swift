// An audio file another app shares becomes a song, opened at once; iOS's Inbox copy goes once it is imported.
import XCTest
@testable import K7Rec

@MainActor
final class ShareTests: XCTestCase {
    func testASharedFileIsImportedAndItsSongOpened() async {
        let library = FakeSongLibrary()
        let model = AppModel(library: library)
        model.looksUpLyrics = false
        let url = URL(fileURLWithPath: "/tmp/jam.m4a")
        await model.openShared(url)
        XCTAssertEqual(library.imported, [url])
        XCTAssertEqual(model.sharedSong, library.songs.first { $0.title == "jam" }?.id)
        XCTAssertNotNil(model.sharedSong)
    }

    func testOnlyTheInboxCopyIsRemoved() throws {
        let docs = try tempFolder()
        let inbox = docs.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let copy = inbox.appendingPathComponent("jam.m4a"), own = docs.appendingPathComponent("jam.m4a")
        for f in [copy, own] { try Data("x".utf8).write(to: f) }
        AppModel.dropInboxCopy(own, documents: docs)
        AppModel.dropInboxCopy(copy, documents: docs)
        XCTAssertTrue(FileManager.default.fileExists(atPath: own.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }
}
