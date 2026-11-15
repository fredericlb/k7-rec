// Debug builds file the audio of `-SeedTake <path>` as a take, so a take's page can be reached without recording.
import Foundation
import RehearsalAudio
import RehearsalStore

#if DEBUG
extension StoreTakeRecorder {
    func seed(from source: URL) async {
        guard let read = try? EnvelopeReader.read(url: source) else { return }
        let name = "take-seed.\(source.pathExtension)"
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        try? FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
        let levelled = read.envelope.scaled(by: Gain.envelope(rawPeak: read.envelope.peak))
        try? await store.put(RehearsalStore.Take(
            id: "seed", title: "Seeded take", duration: read.durationSec, envelope: levelled.samples.map { Float($0) }, gain: 1, audioPath: name))
    }
}
#endif
