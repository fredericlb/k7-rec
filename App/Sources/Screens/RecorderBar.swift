// The bar that stays above the content while a take runs; never a dialog.
import SwiftUI

struct RecorderBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            HStack(spacing: 16) {
                Image(systemName: "circle.fill").foregroundStyle(model.recorder.paused ? .gray : .red)
                Text(format(model.recorder.elapsed)).monospacedDigit()
                ProgressView(value: min(1, model.recorder.level)).frame(maxWidth: .infinity)
                Button {
                    if model.recorder.paused { model.recorder.resume() } else { model.recorder.pause() }
                } label: { Image(systemName: model.recorder.paused ? "play.fill" : "pause.fill") }
                Button { Task { await model.stopTake() } } label: { Image(systemName: "stop.fill") }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func format(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
