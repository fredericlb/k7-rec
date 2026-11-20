// The Takes list, newest first: a play button on each row, and the row opens the take.
import SwiftUI

struct TakesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var metrics: Metrics { Metrics(sizeClass) }
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            // A ZStack, not an overlay: an overlay of the scroll view proposed no width, and the empty state wrapped at every word.
            ZStack {
                ScrollView {
                    CardRows(items: model.recorder.takes, separatorInset: 68) { take in
                        let playing = model.player.loadedID == take.id && model.player.isPlaying
                        HStack(spacing: 10) {
                            Button {
                                if let url = take.audioURL { model.togglePlay(id: take.id, url: url) }
                            } label: {
                                Image(systemName: playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18)).foregroundStyle(k7.accentIcon)
                                    .frame(width: K7Size.touch, height: K7Size.touch)
                                    .background(k7.accentTile, in: Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(playing ? "Pause" : "Play")
                            NavigationLink(value: take.id) {
                                RowLabel(title: take.title, second: take.date.formatted(date: .abbreviated, time: .shortened), value: clock(take.duration)) { EmptyView() }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 14).padding(.trailing, K7Space.s16)
                    }
                    .padding(.horizontal, metrics.margin).padding(.top, 8)
                    .opacity(model.recorder.takes.isEmpty ? 0 : 1)
                }
                if model.recorder.takes.isEmpty {
                    EmptyState(symbol: "waveform", title: "No takes yet", sentence: "Press the red dot beside the tabs to record one.")
                }
            }
            .screenBackground()
            .k7Header("Takes", subtitle: count(model.recorder.takes.count, "take"))
            .navigationDestination(for: String.self) { TakeScreen(takeID: $0) }
            .onChange(of: model.stoppedTake, initial: true) { _, id in
                guard let id else { return }
                path = [id]
                model.stoppedTake = nil
            }
        }
    }
}
