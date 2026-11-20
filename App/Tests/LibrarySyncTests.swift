import RehearsalStore
import XCTest
@testable import K7Rec

/// Two "devices" are two stores and two defaults suites sharing one records folder.
final class LibrarySyncTests: XCTestCase {
    private var folder: URL!
    private var suites: [String] = []

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
    }

    private func device() throws -> (Store, LibrarySync) {
        let name = "sync-\(UUID().uuidString)"
        suites.append(name)
        let store = try Store()
        return (store, LibrarySync(store: store, records: folder, defaults: UserDefaults(suiteName: name)!))
    }

    private func seed(_ store: Store) async throws {
        try await store.saveSong(RehearsalStore.Song(id: "s1", title: "Blue", tags: ["a"]), files: [SongFile(id: "s1:lyrics.txt", kind: .lyrics, path: "Blue/lyrics.txt", name: "lyrics.txt")])
        try await store.put(RehearsalStore.Take(id: "t1", songId: "s1", title: "Take", duration: 9, envelope: [0.5, 1], audioPath: "t1.m4a"))
        try await store.put(Moment(id: "m1", recordingPath: "t1.m4a", startSec: 1, endSec: 5, text: "Verse"))
        try await store.put(Marker(id: "k1", recordingPath: "t1.m4a", atSec: 2, comment: "Here"))
    }

    func testARecordTravelsToAnotherDevice() async throws {
        let (a, syncA) = try device(), (b, syncB) = try device()
        try await seed(a)
        await syncA.run()
        await syncB.run()
        let take = try await b.get(RehearsalStore.Take.self, "t1")
        XCTAssertEqual(take?.envelope, [0.5, 1])
        let moments = try await b.moments(of: "t1.m4a")
        XCTAssertEqual(moments.map(\.text), ["Verse"])
        let song = try await b.get(RehearsalStore.Song.self, "s1")
        XCTAssertEqual(song?.tags, ["a"])
        let files = try await b.list(Query<SongFile>())
        XCTAssertEqual(files.count, 1)
    }

    func testARemoteEditReplacesTheLocalRowAndALocalEditGoesOut() async throws {
        let (a, syncA) = try device(), (b, syncB) = try device()
        try await seed(a)
        await syncA.run(); await syncB.run()
        _ = try await a.write { tx in if var m = try tx.get(Moment.self, "m1") { m.text = "Chorus"; try tx.put(m) } }
        await syncA.run(); await syncB.run()
        let renamed = try await b.get(Moment.self, "m1")
        XCTAssertEqual(renamed?.text, "Chorus")
        _ = try await b.write { tx in if var t = try tx.get(RehearsalStore.Take.self, "t1") { t.title = "Gig"; try tx.put(t) } }
        await syncB.run(); await syncA.run()
        let retitled = try await a.get(RehearsalStore.Take.self, "t1")
        XCTAssertEqual(retitled?.title, "Gig")
    }

    func testADeletionTravelsBothWays() async throws {
        let (a, syncA) = try device(), (b, syncB) = try device()
        try await seed(a)
        await syncA.run(); await syncB.run()
        try await a.deleteTakeWithMoments("t1")
        syncA.markDeleted("take-t1.json")
        await syncA.run(); await syncB.run()
        let gone = try await b.get(RehearsalStore.Take.self, "t1")
        XCTAssertNil(gone)
        let moments = try await b.moments(of: "t1.m4a")
        XCTAssertTrue(moments.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("take-t1.json").path))
    }

    func testAFileStillInICloudIsNeverReadAsADeletion() async throws {
        let (a, syncA) = try device()
        try await seed(a)
        await syncA.run()
        let real = folder.appendingPathComponent("take-t1.json")
        try FileManager.default.moveItem(at: real, to: folder.appendingPathComponent(".take-t1.json.icloud"))
        await syncA.run()
        let kept = try await a.get(RehearsalStore.Take.self, "t1")
        XCTAssertNotNil(kept)
    }

    func testANewDeviceWithNoStateTakesTheFilesAndNeverDeletesThem() async throws {
        let (a, syncA) = try device(), (b, syncB) = try device()
        try await seed(a)
        await syncA.run(); await syncB.run()
        let (fresh, syncFresh) = try device()
        await syncFresh.run()
        let taken = try await fresh.get(RehearsalStore.Take.self, "t1")
        XCTAssertNotNil(taken)
        _ = (b, syncB)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("take-t1.json").path))
    }

    func testARecordFileThatIsGoneIsWrittenAgainAndNeverReadAsADeletion() async throws {
        let (a, syncA) = try device(), (b, syncB) = try device()
        try await seed(a)
        await syncA.run(); await syncB.run()
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) { try FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
        await syncB.run()
        let kept = try await b.get(RehearsalStore.Take.self, "t1")
        let moments = try await b.moments(of: "t1.m4a")
        XCTAssertNotNil(kept)
        XCTAssertEqual(moments.count, 1)
        let song = try await b.get(RehearsalStore.Song.self, "s1")
        XCTAssertNotNil(song)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("take-t1.json").path), "the file is back")
    }

    func testADeviceThatNeverSyncedARecordKeepsItWhenATombstoneExists() async throws {
        let (a, syncA) = try device(), (b, syncB) = try device()
        try await seed(a)
        await syncA.run()
        try await a.deleteTakeWithMoments("t1")
        syncA.markDeleted("take-t1.json")
        await syncA.run()
        // B made its own take with another id and never saw t1; the tombstone of t1 touches nothing of B's.
        try await b.put(RehearsalStore.Take(id: "own", title: "Mine", audioPath: "own.m4a"))
        await syncB.run()
        let own = try await b.get(RehearsalStore.Take.self, "own")
        XCTAssertNotNil(own)
    }

    func testRowsThatAreMissingAreRebuiltNeverAnnouncedAsDeleted() async throws {
        let (a, syncA) = try device(), (b, syncB) = try device()
        try await seed(a)
        await syncA.run(); await syncB.run()
        // B's rows vanish (a bug, a reinstall that kept its defaults): the records are still there.
        try await b.deleteTakeWithMoments("t1")
        await syncB.run()
        let back = try await b.get(RehearsalStore.Take.self, "t1")
        XCTAssertNotNil(back)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("take-t1.json.deleted").path))
        await syncA.run()
        let still = try await a.get(RehearsalStore.Take.self, "t1")
        XCTAssertNotNil(still)
    }

    func testARecordThatDoesNotDecodeIsNotCountedAsSynced() async throws {
        let (b, syncB) = try device()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: folder.appendingPathComponent("take-bad.json"))
        await syncB.run()
        let rows = try await b.list(Query<RehearsalStore.Take>())
        XCTAssertTrue(rows.isEmpty)
        try await seed(b)
        let good = try await LibrarySync(store: b, records: folder, defaults: UserDefaults(suiteName: "x-\(UUID().uuidString)")!).snapshot()
        try good["take-t1.json"]!.write(to: folder.appendingPathComponent("take-bad.json"))
        let report = await syncB.run()
        XCTAssertFalse(report.changed.isEmpty || report.records == 0, "the fixed file is read on the next pass")
    }

    func testASongRecordAsTheRepairWroteItIsApplied() async throws {
        let (b, syncB) = try device()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"{"files":[{"id":"20a2:original.mp3","kind":"audio","mime":"","name":"original","path":"Je rêve 5072f339/original.mp3","position":0,"songId":"20a2"},{"id":"20a2:lyrics.txt","kind":"lyrics","mime":"","name":"lyrics.txt","path":"Je rêve 5072f339/lyrics.txt","position":1,"songId":"20a2"}],"song":{"artist":"Zaho de Sagazan","createdAt":1794762023.108835,"folder":"Je rêve 5072f339","id":"20a2","source":"file","storeId":"","tags":[],"title":"Je rêve","uuid":"20a2"}}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("song-20a2.json"))
        await syncB.run()
        let song = try await b.get(RehearsalStore.Song.self, "20a2")
        XCTAssertEqual(song?.title, "Je rêve")
        let files = try await b.list(Query<SongFile>())
        XCTAssertEqual(files.count, 2)
    }
}
