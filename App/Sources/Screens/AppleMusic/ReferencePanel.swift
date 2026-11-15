// A streamed song's player strip: a seekable position and the one line that says why there is no waveform.
// What a reader gets wrong: the position is Apple's player's, polled on a timer that runs only while it plays.
import SwiftUI

struct ReferencePanel: View {
    @Environment(AppModel.self) private var model
    let song: Song
    @State private var dragging: Double?

    private var loaded: Bool { model.reference.loadedID == song.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let length = max(loaded ? model.reference.duration : 0, 0)
                HStack {
                    Text(time(dragging ?? (loaded ? model.reference.position : 0))).monospacedDigit().font(.caption)
                    Slider(value: Binding(get: { dragging ?? (loaded ? model.reference.position : 0) }, set: { dragging = $0 }), in: 0...max(length, 1)) { editing in
                        if !editing, let to = dragging { model.reference.seek(to: to); dragging = nil }
                    }
                    .disabled(length == 0)
                    .accessibilityIdentifier("referenceSlider")
                    Text(time(length)).monospacedDigit().font(.caption)
                }
            }
            Text("Streamed from Apple Music: its sound is not ours to read, so it has no waveform, loop or moments.")
                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("referenceWhy")
        }
        .padding(.horizontal).padding(.bottom, 6)
    }

    private func time(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
}
