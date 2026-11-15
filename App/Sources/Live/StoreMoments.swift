// Moments and pins over the store: a recording is named by its take's file, as the store's rules expect.
// What a reader gets wrong: deleting a moment goes through the store's rule, which takes its own markers along.
import Foundation
import RehearsalAudio
import RehearsalStore

@MainActor
final class StoreMoments: MomentKeeping {
    private let store: Store

    init(store: Store) { self.store = store }

    func moments(of recording: String) async -> [SavedMoment] {
        ((try? await store.moments(of: recording)) ?? []).map { SavedMoment(id: $0.id, title: $0.text, start: $0.startSec, end: $0.endSec) }
    }

    func pins(of recording: String) async -> [Pin] {
        let own = Query<Marker>(where: [Filter("recordingPath", equals: .text(recording)), Filter("momentId", equals: "")], orderBy: "atSec")
        return ((try? await store.list(own)) ?? []).map { Pin(id: $0.id, at: $0.atSec, note: $0.comment) }
    }

    func save(recording: String, recordedAt: Date, span: ClosedRange<TimeInterval>, title: String, envelope: [Double]) async {
        let step = Double(defaultEnvelopeIntervalMs) / 1000
        let lo = min(envelope.count, max(0, Int(span.lowerBound / step)))
        let hi = min(envelope.count, max(lo, Int((span.upperBound / step).rounded(.up))))
        let row = Moment(
            recordingPath: recording, recordedAt: recordedAt.timeIntervalSince1970, startSec: span.lowerBound,
            endSec: span.upperBound, text: title, envelope: envelope[lo..<hi].map { Float($0) })
        try? await store.put(row)
    }

    func renameMoment(id: String, title: String) async {
        _ = try? await store.write { tx in if var m = try tx.get(Moment.self, id) { m.text = title; try tx.put(m) } }
    }

    func deleteMoment(id: String) async { try? await store.deleteMoment(id) }

    func addPin(recording: String, at seconds: TimeInterval, note: String) async {
        try? await store.put(Marker(recordingPath: recording, atSec: seconds, comment: note))
    }

    func renamePin(id: String, note: String) async {
        _ = try? await store.write { tx in if var m = try tx.get(Marker.self, id) { m.comment = note; try tx.put(m) } }
    }

    func deletePin(id: String) async { try? await store.delete(Marker.self, id) }
}
