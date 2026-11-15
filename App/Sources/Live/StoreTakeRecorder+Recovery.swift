// Finishes the raw takes a crash left in the Takes folder, once, at launch.
// What a reader gets wrong: a recovered take has no song (the raw file never knew it) and says so in its title.
import Foundation
import RehearsalAudio
import RehearsalStore

extension StoreTakeRecorder {
    /// Each leftover becomes a saved take; the raw file goes only after its row is written.
    @discardableResult
    func recoverLeftovers() async -> Int {
        guard !isRecording else { return 0 }
        var saved = 0
        for raw in TakeRecorder.leftovers(in: folder) {
            let attributes = (try? FileManager.default.attributesOfItem(atPath: raw.path)) ?? [:]
            let started = (attributes[.creationDate] as? Date) ?? (attributes[.modificationDate] as? Date) ?? .now
            guard let result = try? await TakeRecorder.recover(raw: raw) else { continue }
            let title = "Recovered take " + started.formatted(date: .abbreviated, time: .shortened)
            do { try await store.put(row(of: result, songID: "", title: title, date: started)) } catch { continue }
            result.confirmSaved()
            saved += 1
        }
        return saved
    }
}
