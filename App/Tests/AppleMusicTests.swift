// Apple Music without a library: items are fakes, the exporter copies a wav, the store is in memory.
import RehearsalStore
import XCTest
@testable import Rehearsal

struct FakeItem: MediaItemInfo {
    var itemID = "1234567890123"
    var title = "Blue"
    var artist = "Joni"
    var album = "Blue"
    var duration: TimeInterval = 180
    var assetURL: URL?
    var hasProtectedAsset = false
    var playbackStoreID = ""
}

struct CopyExporter: AudioExporting {
    var fail: Error?
    func export(from source: URL, to destination: URL, progress: @Sendable (Double) -> Void) async throws {
        if let fail { try Data("partial".utf8).write(to: destination); throw fail }
        try FileManager.default.copyItem(at: source, to: destination)
        progress(1)
    }
}

@MainActor
final class AppleMusicTests: XCTestCase {
    private func rig(exporter: AudioExporting = CopyExporter()) throws -> (AppleMusicWriter, Store, URL) {
        let root = try tempFolder()
        let store = try Store()
        return (AppleMusicWriter(store: store, songs: root.appendingPathComponent("Songs"), exporter: exporter), store, root)
    }

    private func wav(_ root: URL) throws -> URL {
        let url = root.appendingPathComponent("src.wav")
        try makeWav(at: url, seconds: 1, amp: 0.5)
        return url
    }

    func testPlanSeparatesReadableFromStreamedFromNothing() {
        let file = URL(fileURLWithPath: "/x.m4a")
        XCTAssertEqual(AppleMusic.plan(for: FakeItem(assetURL: file)), .exportFile)
        XCTAssertEqual(AppleMusic.plan(for: FakeItem(assetURL: file, hasProtectedAsset: true, playbackStoreID: "77")), .reference(storeID: "77"))
        XCTAssertEqual(AppleMusic.plan(for: FakeItem(playbackStoreID: "77")), .reference(storeID: "77"))
        guard case .skip = AppleMusic.plan(for: FakeItem(hasProtectedAsset: true)) else { return XCTFail("an item with no sound and no id is skipped") }
    }

    func testReadableItemBecomesAnOrdinaryAudioSongOnce() async throws {
        let (writer, store, root) = try rig()
        let item = FakeItem(assetURL: try wav(root))
        for _ in 0..<2 { _ = await writer.write([item]) { _, _ in } }
        let songs = try await store.list(Query<RehearsalStore.Song>())
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs[0].source, .file)
        XCTAssertEqual(songs[0].title, "Blue")
        XCTAssertEqual(songs[0].artist, "Joni")
        let files = try await store.list(Query<SongFile>())
        XCTAssertEqual(files.map(\.kind), [.audio])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Songs").appendingPathComponent(files[0].path).path))
    }

    func testStreamedItemBecomesAReferenceWithNoFile() async throws {
        let (writer, store, _) = try rig()
        let out = await writer.write([FakeItem(playbackStoreID: "9988")]) { _, _ in }
        XCTAssertEqual(out.referenced, 1)
        let song = try await store.list(Query<RehearsalStore.Song>()).first
        XCTAssertEqual(song?.source, .appleMusicReference)
        XCTAssertEqual(song?.storeId, "9988")
        let files = try await store.list(Query<SongFile>())
        XCTAssertTrue(files.isEmpty)
    }

    func testAnItemWithNothingToPlayLeavesNoRow() async throws {
        let (writer, store, _) = try rig()
        let out = await writer.write([FakeItem()]) { _, _ in }
        XCTAssertEqual(out.skipped.count, 1)
        let songs = try await store.list(Query<RehearsalStore.Song>())
        XCTAssertTrue(songs.isEmpty)
    }

    func testACancelledExportLeavesNeitherFolderNorRow() async throws {
        let (writer, store, root) = try rig(exporter: CopyExporter(fail: CancellationError()))
        let out = await writer.write([FakeItem(assetURL: try wav(root))]) { _, _ in }
        XCTAssertTrue(out.cancelled)
        let songs = try await store.list(Query<RehearsalStore.Song>())
        XCTAssertTrue(songs.isEmpty)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Songs").path)) ?? []
        XCTAssertTrue(left.isEmpty)
    }

    func testARefusedAuthorizationImportsNothing() async throws {
        let root = try tempFolder()
        let store = try Store()
        let source = LiveAppleMusicSource(authorizer: FakeMusicAuthorizer(access: .denied, answer: .denied), store: store, songs: root, exporter: CopyExporter())
        let model = AppModel(appleMusic: source)
        let allowed = await model.allowAppleMusic()
        XCTAssertFalse(allowed)
        XCTAssertNotNil(model.notice)
        await model.importAppleMusic([FakeItem(playbackStoreID: "9988")])
        let songs = try await store.list(Query<RehearsalStore.Song>())
        XCTAssertTrue(songs.isEmpty)
    }

    func testAGrantedAuthorizationImports() async throws {
        let root = try tempFolder()
        let store = try Store()
        let source = LiveAppleMusicSource(authorizer: FakeMusicAuthorizer(), store: store, songs: root, exporter: CopyExporter())
        let model = AppModel(appleMusic: source)
        let allowed = await model.allowAppleMusic()
        XCTAssertTrue(allowed)
        await model.importAppleMusic([FakeItem(playbackStoreID: "9988")])
        let songs = try await store.list(Query<RehearsalStore.Song>())
        XCTAssertEqual(songs.count, 1)
    }

    func testReferenceRowReachesTheSongList() async throws {
        let root = try tempFolder()
        let store = try Store()
        let lib = StoreSongLibrary(store: store, songsFolder: root)
        try await store.put(RehearsalStore.Song(id: "r", title: "Streamed", source: .appleMusicReference, storeId: "55"))
        await lib.refresh()
        XCTAssertEqual(lib.songs.first?.referenceID, "55")
        XCTAssertTrue(lib.songs.first?.isReference == true)
    }

    func testReferencePlayingKeepsTheSessionAndSilencesTheFilePlayer() {
        var deactivated = 0
        let files = FakeTakePlayer(), ref = FakeReferencePlayer()
        let model = AppModel(player: files, reference: ref, deactivate: { deactivated += 1 })
        files.load(id: "f", url: URL(fileURLWithPath: "/x")); files.toggle()
        model.toggleReference(Song(id: "r", title: "S", artist: "", referenceID: "55"))
        XCTAssertFalse(files.isPlaying)
        XCTAssertTrue(ref.isPlaying)
        deactivated = 0
        model.restSession()
        XCTAssertEqual(deactivated, 0)
        ref.pause()
        XCTAssertEqual(deactivated, 1)
    }
}

@MainActor
final class AppleMusicKeepsTests: XCTestCase {
    private func rig(exporter: AudioExporting = CopyExporter()) throws -> (AppleMusicWriter, Store, URL) {
        let root = try tempFolder()
        let store = try Store()
        return (AppleMusicWriter(store: store, songs: root.appendingPathComponent("Songs"), exporter: exporter), store, root)
    }

    private func wav(_ root: URL) throws -> URL {
        let url = root.appendingPathComponent("src.wav")
        try makeWav(at: url, seconds: 1, amp: 0.5)
        return url
    }

    func testPickingAnItemAgainKeepsItsTextsAndTags() async throws {
        let (writer, store, root) = try rig()
        let item = FakeItem(assetURL: try wav(root))
        _ = await writer.write([item]) { _, _ in }
        let rows = try await store.list(Query<RehearsalStore.Song>())
        let row = try XCTUnwrap(rows.first)
        let lib = StoreSongLibrary(store: store, songsFolder: root.appendingPathComponent("Songs"))
        await lib.refresh()
        _ = await lib.saveText(.lyrics, "mine", for: lib.songs[0])
        _ = await lib.setTags(["x"], for: lib.songs[0])

        _ = await writer.write([item]) { _, _ in }
        await lib.refresh()

        XCTAssertEqual(lib.songs.count, 1)
        XCTAssertEqual(lib.songs[0].id, row.id)
        XCTAssertEqual(lib.songs[0].lyrics, "mine")
        XCTAssertEqual(lib.songs[0].tags, ["x"])
        XCTAssertNotNil(lib.songs[0].audioURL)
    }

    func testAFailedExportKeepsTheOldCopy() async throws {
        let (writer, store, root) = try rig()
        let item = FakeItem(assetURL: try wav(root))
        _ = await writer.write([item]) { _, _ in }
        let failing = AppleMusicWriter(store: store, songs: root.appendingPathComponent("Songs"), exporter: CopyExporter(fail: CancellationError()))

        let out = await failing.write([item]) { _, _ in }

        XCTAssertTrue(out.cancelled)
        let files = try await store.list(Query<SongFile>())
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Songs").appendingPathComponent(files[0].path).path))
    }

    func testRefusalsSayWhy() {
        XCTAssertNil(AppleMusic.refusal(.authorized))
        XCTAssertTrue(AppleMusic.refusal(.restricted)!.contains("restricted"))
        XCTAssertTrue(AppleMusic.refusal(.denied)!.contains("Settings"))
    }
}
