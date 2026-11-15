// The detector's sliders and the spans it found; every move of a slider runs the detector again.
import RehearsalAudio
import SwiftUI

struct DetectPanel: View {
    let moments: TakeMoments
    let playing: (ClosedRange<TimeInterval>) -> Bool
    let play: (ClosedRange<TimeInterval>) -> Void
    let save: (DetectedMoment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Floor", value: String(format: "%.0f%%", moments.sift.floor * 100))
            Slider(value: Binding(get: { moments.sift.floor }, set: { moments.setFloor($0) }), in: 0...max(moments.peak, 0.01))
                .accessibilityLabel("Floor")
            LabeledContent("Silence", value: String(format: "%.1f s", moments.sift.silence))
            Slider(value: Binding(get: { moments.sift.silence }, set: { moments.setSilence($0) }), in: MomentSift.silenceRange, step: 0.5)
                .accessibilityLabel("Silence")
            if moments.found.isEmpty {
                Text("Nothing found: lower the floor or shorten the silence.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(moments.found.enumerated()), id: \.offset) { _, m in
                HStack {
                    Button { play(m.startSec...m.endSec) } label: {
                        Image(systemName: playing(m.startSec...m.endSec) ? "pause.fill" : "play.fill").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(playing(m.startSec...m.endSec) ? "Pause span" : "Play span")
                    Text("\(clock(m.startSec)) to \(clock(m.endSec))").monospacedDigit()
                    Text(String(format: "%.0f s", m.durationSec)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") { save(m) }.buttonStyle(.bordered)
                }
            }
        }
    }
}

func clock(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
