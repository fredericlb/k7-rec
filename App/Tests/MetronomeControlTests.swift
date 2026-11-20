// The metronome control follows the click when the system stops it.
import RehearsalAudio
import XCTest
@testable import K7Rec

@MainActor
final class MetronomeControlTests: XCTestCase {
    func testACallStopsTheClickAndTheControlSaysSo() throws {
        let session = ScriptedSession()
        let control = MetronomeControl(metronome: Metronome(session: session))
        var stopped = 0
        control.onStop = { stopped += 1 }
        control.toggle()
        try XCTSkipUnless(control.running, "no audio engine here")

        session.send(.began)

        XCTAssertFalse(control.running)
        XCTAssertEqual(stopped, 1)
    }
}
