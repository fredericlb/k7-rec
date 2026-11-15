// What the recorder bar and the Takes list need from the audio package.
import Foundation

struct Take: Identifiable, Hashable {
    let id: String
    var songTitle: String
    var date: Date
    var duration: TimeInterval
}

protocol TakeRecording: AnyObject {
    var level: Double { get }
    var elapsed: TimeInterval { get }
    var paused: Bool { get }
    var takes: [Take] { get }
    func start(songID: String)
    func pause()
    func resume()
    func stop()
}

final class FakeTakeRecorder: TakeRecording {
    private var startedAt: Date?
    private(set) var paused = false
    private(set) var takes: [Take] = [
        Take(id: "t1", songTitle: "Blue Monday Jam", date: .now.addingTimeInterval(-86_400), duration: 213),
        Take(id: "t2", songTitle: "Slow Waltz", date: .now.addingTimeInterval(-3_600), duration: 95),
    ]
    private var title = ""

    var level: Double { paused || startedAt == nil ? 0 : 0.3 + 0.2 * sin(Date().timeIntervalSinceReferenceDate * 6) }
    var elapsed: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    func start(songID: String) {
        title = songID
        startedAt = Date()
        paused = false
    }

    func pause() { paused = true }
    func resume() { paused = false }

    func stop() {
        takes.insert(Take(id: UUID().uuidString, songTitle: "Song \(title)", date: .now, duration: elapsed), at: 0)
        startedAt = nil
    }
}
