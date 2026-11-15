// A take survives a crash, a call and a route change, and the headset microphone is opt-in.
import RehearsalAudio
import RehearsalStore
import XCTest
@testable import Rehearsal

@MainActor
final class TakeSafetyTests: XCTestCase {
    private func settle(until check: () -> Bool) async {
        for _ in 0..<100 where !check() { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    func testARawTakeLeftByACrashIsSavedAtLaunchAndItsRawFileGoes() async throws {
        let folder = try tempFolder()
        let raw = try makeRawTake(in: folder, seconds: 3, amp: 0.2)
        let store = try Store()
        let rec = StoreTakeRecorder(store: store, takesFolder: folder, askMicrophone: { true })

        let saved = await rec.recoverLeftovers()

        XCTAssertEqual(saved, 1)
        let rows = try await store.list(Query<RehearsalStore.Take>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].title.hasPrefix("Recovered take"))
        XCTAssertEqual(rows[0].duration, 3, accuracy: 0.05)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(rows[0].audioPath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path))
        let again = await rec.recoverLeftovers()
        XCTAssertEqual(again, 0)
    }

    func testACallPausesTheTakeWithItsReasonAndResumeKeepsOneTake() async throws {
        let input = ScriptedInput()
        let session = ScriptedSession()
        let store = try Store()
        let rec = StoreTakeRecorder(store: store, takesFolder: try tempFolder(), makeInput: { input }, makeSession: { session }, askMicrophone: { true })
        _ = await rec.start(songID: "", title: "Call")
        input.push(seconds: 1, amp: 0.3)

        session.send(.began)
        await settle { rec.paused }

        XCTAssertTrue(rec.paused)
        XCTAssertEqual(rec.pauseCause, .interrupted)
        await rec.resume()
        XCTAssertFalse(rec.paused)
        XCTAssertNil(rec.pauseCause)
        input.push(seconds: 1, amp: 0.3)
        await rec.stop()
        let rows = try await store.list(Query<RehearsalStore.Take>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].duration, 2, accuracy: 0.05)
    }

    func testAUserPauseSaysSo() async throws {
        let rec = StoreTakeRecorder(store: try Store(), takesFolder: try tempFolder(), makeInput: { ScriptedInput() }, askMicrophone: { true })
        _ = await rec.start(songID: "", title: "x")
        rec.pause()
        XCTAssertEqual(rec.pauseCause, .user)
    }

    func testAResumeOnAnotherRateContinuesTheSameTake() async throws {
        let box = InputBox()
        let folder = try tempFolder()
        let store = try Store()
        let rec = StoreTakeRecorder(store: store, takesFolder: folder, makeInput: { box.make() }, makeSession: { ScriptedSession() }, askMicrophone: { true })
        _ = await rec.start(songID: "", title: "Headset")
        box.current.push(seconds: 1, amp: 0.3)
        rec.pause()
        box.rate = 16_000
        box.current.sampleRate = 16_000

        await rec.resume()

        XCTAssertFalse(rec.paused, "the take went on")
        box.current.push(seconds: 1, amp: 0.3)
        await rec.stop()
        let rows = try await store.list(Query<RehearsalStore.Take>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].duration, 2, accuracy: 0.1)
        XCTAssertEqual((try FileManager.default.contentsOfDirectory(atPath: folder.path)).count, 1, "one m4a, no raw part left")
    }

    func testTheHeadsetMicrophoneIsAskedForOnlyWhenTheSettingIsOn() async throws {
        let session = ScriptedSession()
        var on = false
        let rec = StoreTakeRecorder(
            store: try Store(), takesFolder: try tempFolder(), makeInput: { ScriptedInput() }, makeSession: { session },
            askMicrophone: { true }, headsetInput: { on })
        _ = await rec.start(songID: "", title: "a")
        await rec.stop()
        on = true
        _ = await rec.start(songID: "", title: "b")

        XCTAssertEqual(session.headsetAsked, [false, true])
    }

    func testTheHeadsetSettingIsOffByDefaultAndKept() {
        let suite = UserDefaults(suiteName: "rehearsal-test-\(UUID().uuidString)")!
        let prefs = SongPrefs(defaults: suite)
        XCTAssertFalse(prefs.headsetInput)
        prefs.headsetInput = true
        XCTAssertTrue(SongPrefs(defaults: suite).headsetInput)
    }

    func testTheSessionIsGivenBackWhenTheTakeStops() async throws {
        var rested = 0
        let input = ScriptedInput()
        let rec = StoreTakeRecorder(store: try Store(), takesFolder: try tempFolder(), makeInput: { input }, askMicrophone: { true })
        let model = AppModel(recorder: rec, deactivate: { rested += 1 })
        await model.startTake()
        input.push(seconds: 1, amp: 0.3)
        model.restSession()
        XCTAssertEqual(rested, 0, "a take keeps the session")

        await model.stopTake()

        XCTAssertEqual(rested, 1)
    }
}
