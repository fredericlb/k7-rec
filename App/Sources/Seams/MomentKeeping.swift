// What a take's page needs to keep: saved moments and the named pins on its recording, by the recording's file name.
import Foundation

struct SavedMoment: Identifiable, Hashable {
    let id: String
    var title: String
    var start: TimeInterval
    var end: TimeInterval
    var span: ClosedRange<TimeInterval> { start...max(start, end) }
}

struct Pin: Identifiable, Hashable {
    let id: String
    var at: TimeInterval
    var note: String
}

@MainActor
protocol MomentKeeping: AnyObject {
    func moments(of recording: String) async -> [SavedMoment]
    func pins(of recording: String) async -> [Pin]
    /// Saves `span` of `recording`; `envelope` is the take's whole envelope, of which the span's part is kept.
    func save(recording: String, recordedAt: Date, span: ClosedRange<TimeInterval>, title: String, envelope: [Double]) async
    func renameMoment(id: String, title: String) async
    func deleteMoment(id: String) async
    func addPin(recording: String, at seconds: TimeInterval, note: String) async
    func renamePin(id: String, note: String) async
    func deletePin(id: String) async
}

@MainActor
final class FakeMomentKeeper: MomentKeeping {
    private var kept: [String: [SavedMoment]] = [:]
    private var pinned: [String: [Pin]] = [:]

    func moments(of recording: String) async -> [SavedMoment] { kept[recording] ?? [] }
    func pins(of recording: String) async -> [Pin] { pinned[recording] ?? [] }

    func save(recording: String, recordedAt: Date, span: ClosedRange<TimeInterval>, title: String, envelope: [Double]) async {
        kept[recording, default: []].append(SavedMoment(id: UUID().uuidString, title: title, start: span.lowerBound, end: span.upperBound))
    }

    func renameMoment(id: String, title: String) async {
        for key in kept.keys { if let i = kept[key]?.firstIndex(where: { $0.id == id }) { kept[key]?[i].title = title } }
    }

    func deleteMoment(id: String) async { for key in kept.keys { kept[key]?.removeAll { $0.id == id } } }

    func addPin(recording: String, at seconds: TimeInterval, note: String) async {
        pinned[recording, default: []].append(Pin(id: UUID().uuidString, at: seconds, note: note))
    }

    func renamePin(id: String, note: String) async {
        for key in pinned.keys { if let i = pinned[key]?.firstIndex(where: { $0.id == id }) { pinned[key]?[i].note = note } }
    }

    func deletePin(id: String) async { for key in pinned.keys { pinned[key]?.removeAll { $0.id == id } } }
}
