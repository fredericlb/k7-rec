// What the recorder bar and the Takes screens need from the audio package and the store.
import Foundation

struct Take: Identifiable, Hashable {
    let id: String
    var songID = ""
    var title: String
    var date: Date
    var duration: TimeInterval
    var envelope: [Double] = []
    var gain = 1.0
    var audioURL: URL?
}

/// Why a take rests; `.user` is the person's own pause, the others come from the phone.
enum PauseCause: Equatable { case user, inputLost, interrupted }

@MainActor
protocol TakeRecording: AnyObject {
    var level: Double { get }
    var elapsed: TimeInterval { get }
    var paused: Bool { get }
    /// Set while paused: a call or a lost input leaves the take kept and waiting for Resume.
    var pauseCause: PauseCause? { get }
    /// Why the last take or start failed, nil when it did not.
    var failure: String? { get }
    /// Newest first; a listing carries no envelope, `take(id:)` does.
    var takes: [Take] { get }
    /// Returns false when the microphone is refused or the input fails to open.
    func start(songID: String, title: String) async -> Bool
    func pause()
    func resume() async
    func stop() async
    /// Saves the raw takes a crash left behind; returns how many came back.
    @discardableResult func recoverLeftovers() async -> Int
    func take(id: String) async -> Take?
    func rename(id: String, title: String) async
    func delete(id: String) async
}

@MainActor
final class FakeTakeRecorder: TakeRecording {
    private var startedAt: Date?
    private var title = ""
    private(set) var paused = false
    private(set) var pauseCause: PauseCause?
    private(set) var failure: String?
    private(set) var takes: [Take] = [
        Take(id: "t1", title: "Blue Monday Jam", date: .now.addingTimeInterval(-86_400), duration: 213, envelope: Wave.fake.samples),
        Take(id: "t2", title: "Slow Waltz", date: .now.addingTimeInterval(-3_600), duration: 95, envelope: Wave.fake.samples),
    ]

    var level: Double { paused || startedAt == nil ? 0 : 0.3 + 0.2 * sin(Date().timeIntervalSinceReferenceDate * 6) }
    var elapsed: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    func start(songID: String, title: String) async -> Bool {
        self.title = title
        startedAt = Date()
        paused = false
        return true
    }

    func pause() { paused = true; pauseCause = .user }
    func resume() async { paused = false; pauseCause = nil }
    func recoverLeftovers() async -> Int { 0 }

    func stop() async {
        takes.insert(Take(id: UUID().uuidString, title: title, date: .now, duration: elapsed), at: 0)
        startedAt = nil
    }

    func take(id: String) async -> Take? { takes.first { $0.id == id } }

    func rename(id: String, title: String) async {
        if let i = takes.firstIndex(where: { $0.id == id }) { takes[i].title = title }
    }

    func delete(id: String) async { takes.removeAll { $0.id == id } }
}
