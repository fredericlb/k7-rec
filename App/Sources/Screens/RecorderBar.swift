// The bar that stays above the content while a take runs; never a dialog.
// What a reader gets wrong: a call pauses the take, it never ends it; Resume continues the same take.
import SwiftUI

struct RecorderBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            VStack(spacing: 6) {
                if let why = reason { Text(why).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("pauseReason") }
                HStack(spacing: 16) {
                    Image(systemName: "circle.fill").foregroundStyle(model.recorder.paused ? .gray : .red)
                        .accessibilityLabel(model.recorder.paused ? "Paused" : "Recording")
                    Text(format(model.recorder.elapsed)).monospacedDigit()
                    ProgressView(value: min(1, model.recorder.level)).frame(maxWidth: .infinity).accessibilityLabel("Input level")
                    Button {
                        if model.recorder.paused { Task { await model.resumeTake() } } else { model.recorder.pause() }
                    } label: {
                        if model.recorder.pauseCause == .user || !model.recorder.paused {
                            Image(systemName: model.recorder.paused ? "play.fill" : "pause.fill")
                        } else { Text("Resume").bold() }
                    }
                    .target()
                    .accessibilityLabel(model.recorder.paused ? "Resume take" : "Pause take")
                    Button { Task { await model.stopTake() } } label: { Image(systemName: "stop.fill") }
                        .target()
                        .accessibilityLabel("Stop take")
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var reason: String? {
        switch model.recorder.pauseCause {
        case .interrupted: "Paused by a call or another app. The take is kept."
        case .inputLost: "The microphone was lost. The take is kept."
        default: nil
        }
    }

    private func format(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
