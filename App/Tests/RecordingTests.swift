// A scripted input recorded through the app's recorder lands as a Take row with envelope and gain.
import RehearsalStore
import XCTest
@testable import Rehearsal

@MainActor
final class RecordingTests: XCTestCase {
    private func recorder(_ input: ScriptedInput, mic: Bool = true) throws -> (StoreTakeRecorder, Store, URL) {
        let folder = try tempFolder()
        let store = try Store()
        return (StoreTakeRecorder(store: store, takesFolder: folder, makeInput: { input }, askMicrophone: { mic }), store, folder)
    }

    private func settle(until check: () -> Bool) async {
        for _ in 0..<100 where !check() { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    func testRecordedTakeIsSavedWithEnvelopeAndGain() async throws {
        let input = ScriptedInput()
        let (rec, store, folder) = try recorder(input)

        let started = await rec.start(songID: "s1", title: "Blue Monday")
        input.push(seconds: 2, amp: 0.2)
        await rec.stop()

        XCTAssertTrue(started)
        let rows = try await store.list(Query<RehearsalStore.Take>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "Blue Monday")
        XCTAssertEqual(rows[0].songId, "s1")
        XCTAssertEqual(rows[0].duration, 2, accuracy: 0.05)
        XCTAssertEqual(rows[0].envelope.count, 10)
        XCTAssertEqual(rows[0].gain, 1, "the applied gain is baked into the file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(rows[0].audioPath).path))
        await settle { !rec.takes.isEmpty }
        XCTAssertEqual(rec.takes.map(\.title), ["Blue Monday"])
    }

    func testRefusedMicrophoneStartsNothing() async throws {
        let (rec, store, _) = try recorder(ScriptedInput(), mic: false)

        let started = await rec.start(songID: "", title: "x")

        XCTAssertFalse(started)
        let rows = try await store.list(Query<RehearsalStore.Take>())
        XCTAssertTrue(rows.isEmpty)
    }

    func testRenameThenDeleteRemovesRowAndFile() async throws {
        let input = ScriptedInput()
        let (rec, store, folder) = try recorder(input)
        _ = await rec.start(songID: "", title: "Old")
        input.push(seconds: 1, amp: 0.3)
        await rec.stop()
        let id = try await store.list(Query<RehearsalStore.Take>())[0].id

        await rec.rename(id: id, title: "New name")
        let renamed = await rec.take(id: id)
        let path = renamed?.audioURL?.path ?? ""
        await rec.delete(id: id)

        XCTAssertEqual(renamed?.title, "New name")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        let left = try await store.list(Query<RehearsalStore.Take>())
        XCTAssertTrue(left.isEmpty)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.count, 0)
    }
}
