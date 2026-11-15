// The moments side of one take's page: the detector and its sliders, the saved moments and the pins.
// What a reader gets wrong: detection is off whenever a page opens and every slider move re-runs it, in memory.
import Foundation
import Observation
import RehearsalAudio

@Observable @MainActor
final class TakeMoments {
    let take: Take
    @ObservationIgnored private let keeper: MomentKeeping
    private(set) var saved: [SavedMoment] = []
    private(set) var pins: [Pin] = []
    private(set) var found: [DetectedMoment] = []
    private(set) var sift: MomentSift
    private(set) var detecting = false

    init(take: Take, keeper: MomentKeeping) {
        self.take = take
        self.keeper = keeper
        sift = MomentSift(samples: take.envelope)
    }

    var recording: String { take.audioURL?.lastPathComponent ?? "" }
    var peak: Double { take.envelope.max() ?? 0 }

    func setDetecting(_ on: Bool) {
        detecting = on
        run()
    }

    func setFloor(_ value: Double) {
        sift.floor = value
        run()
    }

    func setSilence(_ value: Double) {
        sift.silence = value
        run()
    }

    func load() async {
        saved = await keeper.moments(of: recording)
        pins = await keeper.pins(of: recording)
    }

    /// Keeps a detected span; a span already kept is not kept twice.
    func save(_ moment: DetectedMoment, title: String) async {
        guard !saved.contains(where: { $0.start == moment.startSec && $0.end == moment.endSec }) else { return }
        let name = title.trimmedOr(Self.defaultTitle(at: moment.startSec))
        await keeper.save(recording: recording, recordedAt: take.date, span: moment.startSec...moment.endSec, title: name, envelope: take.envelope)
        await load()
    }

    func rename(_ moment: SavedMoment, to title: String) async {
        await keeper.renameMoment(id: moment.id, title: title.trimmedOr(moment.title))
        await load()
    }

    func delete(_ moment: SavedMoment) async {
        await keeper.deleteMoment(id: moment.id)
        await load()
    }

    func addPin(at seconds: TimeInterval, note: String) async {
        await keeper.addPin(recording: recording, at: min(max(0, seconds), take.duration), note: note.trimmedOr("Marker"))
        await load()
    }

    func rename(_ pin: Pin, to note: String) async {
        await keeper.renamePin(id: pin.id, note: note.trimmedOr(pin.note))
        await load()
    }

    func delete(_ pin: Pin) async {
        await keeper.deletePin(id: pin.id)
        await load()
    }

    nonisolated static func defaultTitle(at seconds: TimeInterval) -> String {
        String(format: "Moment %d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func run() { found = detecting ? sift.detect(take.envelope).moments : [] }
}

private extension String {
    func trimmedOr(_ fallback: String) -> String {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }
}
