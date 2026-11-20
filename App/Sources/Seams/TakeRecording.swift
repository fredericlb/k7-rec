// What the rec button, the take panel and the Takes screens need from the audio package and the store.
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

/// Where a moment of the running take can be heard.
struct Listening { let url: URL; let span: ClosedRange<TimeInterval>; let gain: Double }

@MainActor
protocol TakeRecording: AnyObject {
    var level: Double { get }
    var elapsed: TimeInterval { get }
    var paused: Bool { get }
    /// The last seconds of the running take, levelled 0...1 and padded on the left, ready to draw; empty when none runs.
    var liveSamples: [Double] { get }
    /// The take time at the left edge of `liveSamples`, to place the highlights over it.
    var liveWindowStart: TimeInterval { get }
    /// The moments the detector finds in the running take so far.
    var liveMoments: Int { get }
    /// The moments of the running take, newest last, each with the slice of waveform that draws it.
    var highlights: [Highlight] { get }
    /// Rests the take and says where to hear `highlight`: a file, the span in it and its playback gain; nil when it cannot be heard.
    func listen(to highlight: Highlight) -> Listening?
    /// Set while paused: a call or a lost input leaves the take kept and waiting for Resume.
    var pauseCause: PauseCause? { get }
    /// Why the last take or start failed, nil when it did not.
    var failure: String? { get }
    /// True from a successful start until the take is stopped or lost to a failed continuation.
    var isRecording: Bool { get }
    /// How many raw takes the last recovery could not finish; they stay in the Takes folder.
    var unrecovered: Int { get }
    /// Newest first; a listing carries no envelope, `take(id:)` does.
    var takes: [Take] { get }
    /// Returns false when the microphone is refused or the input fails to open.
    func start(songID: String, title: String) async -> Bool
    func pause()
    func resume() async
    /// Ends the take and saves it; returns the saved take's id, nil when nothing was saved.
    @discardableResult func stop() async -> String?
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
    var isRecording: Bool { startedAt != nil }
    var unrecovered: Int { 0 }
    private(set) var takes: [Take] = [
        Take(id: "t1", title: "Blue Monday Jam", date: .now.addingTimeInterval(-86_400), duration: 213, envelope: Wave.fake.samples),
        Take(id: "t2", title: "Slow Waltz", date: .now.addingTimeInterval(-3_600), duration: 95, envelope: Wave.fake.samples),
    ]

    var liveSamples: [Double] {
        guard startedAt != nil else { return [] }
        let t = elapsed
        return (0..<150).map { 0.15 + 0.5 * abs(sin(Double($0) / 7 + t)) }
    }
    var liveWindowStart: TimeInterval { elapsed - LiveTake.windowSeconds }
    var liveMoments: Int { highlights.count }
    var highlights: [Highlight] {
        (0..<Int(elapsed / 10)).map { Highlight(span: Double($0 * 10)...Double($0 * 10 + 6), samples: Wave.fake.samples) }
    }
    func listen(to highlight: Highlight) -> Listening? { pause(); return nil }
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

    @discardableResult func stop() async -> String? {
        let id = UUID().uuidString
        takes.insert(Take(id: id, title: title, date: .now, duration: elapsed), at: 0)
        startedAt = nil
        return id
    }

    func take(id: String) async -> Take? { takes.first { $0.id == id } }

    func rename(id: String, title: String) async {
        if let i = takes.firstIndex(where: { $0.id == id }) { takes[i].title = title }
    }

    func delete(id: String) async { takes.removeAll { $0.id == id } }
}
