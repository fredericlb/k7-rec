// The take page's logic: the sliders re-run the detector, a span is kept once, and what leaves with a take.
import RehearsalAudio
import RehearsalStore
import XCTest
@testable import Rehearsal

@MainActor
final class MomentsTests: XCTestCase {
    /// 40 s at 200 ms: loud 0-8 s, 14-24 s and 31-38 s (end excluded), quiet between.
    private func take(_ file: String = "a.m4a") -> Rehearsal.Take {
        let samples = (0..<200).map { i -> Double in
            let t = Double(i) * 0.2
            return [0.0..<8, 14..<24, 31..<38].contains { $0.contains(t) } ? 0.8 : 0.01
        }
        return Rehearsal.Take(id: "t1", title: "Take", date: .now, duration: 40, envelope: samples, audioURL: URL(fileURLWithPath: "/x/\(file)"))
    }

    func testTheSlidersRunTheDetectorAgainOnEveryMove() {
        let moments = TakeMoments(take: take(), keeper: FakeMomentKeeper())
        XCTAssertTrue(moments.found.isEmpty, "a page opens without detection")

        moments.setDetecting(true)
        XCTAssertEqual(moments.found.map(\.startSec), [0, 14, 31])
        moments.setSilence(10)
        XCTAssertEqual(moments.found.count, 1, "gaps shorter than 10 s no longer cut")
        moments.setSilence(2)
        moments.setFloor(0.9)
        XCTAssertTrue(moments.found.isEmpty, "nothing is above the floor")
        moments.setDetecting(false)
        moments.setFloor(0.1)
        XCTAssertTrue(moments.found.isEmpty, "turned off, it finds nothing")
    }

    func testASavedMomentKeepsItsSliceAndIsNotSavedTwice() async throws {
        let store = try Store()
        let moments = TakeMoments(take: take(), keeper: StoreMoments(store: store))
        moments.setDetecting(true)
        let first = moments.found[0]

        await moments.save(first, title: "  Intro  ")
        await moments.save(first, title: "again")

        let rows = try await store.moments(of: "a.m4a")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].text, "Intro")
        XCTAssertEqual(rows[0].endSec, 8)
        XCTAssertEqual(rows[0].envelope.count, 40)
        XCTAssertEqual(moments.saved.map(\.title), ["Intro"])
    }

    func testRenamingAndDeletingAMomentTakesItsOwnMarkers() async throws {
        let store = try Store()
        let moments = TakeMoments(take: take(), keeper: StoreMoments(store: store))
        moments.setDetecting(true)
        await moments.save(moments.found[1], title: "Verse")
        await moments.rename(moments.saved[0], to: "Verse 2")
        let id = moments.saved[0].id
        try await store.put(Marker(recordingPath: "a.m4a", momentId: id, atSec: 15))

        XCTAssertEqual(moments.saved.map(\.title), ["Verse 2"])
        await moments.delete(moments.saved[0])

        XCTAssertTrue(moments.saved.isEmpty)
        let markers = try await store.list(Query<Marker>())
        XCTAssertTrue(markers.isEmpty)
    }

    func testPinsAreNamedClampedAndRenamed() async throws {
        let moments = TakeMoments(take: take(), keeper: StoreMoments(store: try Store()))
        await moments.addPin(at: 99, note: "Chorus")
        await moments.addPin(at: 5, note: "  ")
        XCTAssertEqual(moments.pins.map(\.at), [5, 40])
        XCTAssertEqual(moments.pins.map(\.note), ["Marker", "Chorus"])
        await moments.rename(moments.pins[0], to: "Bridge")
        XCTAssertEqual(moments.pins[0].note, "Bridge")
        await moments.delete(moments.pins[1])
        XCTAssertEqual(moments.pins.count, 1)
    }

    func testDeletingATakeTakesItsPinsAndMomentsAndNoOthers() async throws {
        let input = ScriptedInput()
        let folder = try tempFolder()
        let store = try Store()
        let rec = StoreTakeRecorder(store: store, takesFolder: folder, makeInput: { input }, askMicrophone: { true })
        _ = await rec.start(songID: "", title: "Mine")
        input.push(seconds: 1, amp: 0.3)
        await rec.stop()
        let row = try await store.list(Query<RehearsalStore.Take>())[0]
        let keeper = StoreMoments(store: store)
        await keeper.save(recording: row.audioPath, recordedAt: .now, span: 0...1, title: "m", envelope: [])
        await keeper.addPin(recording: row.audioPath, at: 0.5, note: "p")
        await keeper.save(recording: "other.m4a", recordedAt: .now, span: 0...1, title: "keep", envelope: [])
        await keeper.addPin(recording: "other.m4a", at: 0.5, note: "keep")

        await rec.delete(id: row.id)

        let moments = try await store.list(Query<Moment>())
        let pins = try await store.list(Query<Marker>())
        XCTAssertEqual(moments.map(\.text), ["keep"])
        XCTAssertEqual(pins.map(\.comment), ["keep"])
    }
}
