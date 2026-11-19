// The Takes list, newest first, with a red-dot button that starts a take and a row that opens it.
import SwiftUI

struct TakesScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List(model.recorder.takes) { take in
                HStack {
                    Button {
                        if let url = take.audioURL { model.togglePlay(id: take.id, url: url) }
                    } label: {
                        Image(systemName: model.player.loadedID == take.id && model.player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(model.player.loadedID == take.id && model.player.isPlaying ? "Pause" : "Play")
                    .buttonStyle(.borderless)
                    NavigationLink(value: take.id) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(take.title)
                                Text(take.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%d:%02d", Int(take.duration) / 60, Int(take.duration) % 60)).monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if model.recorder.takes.isEmpty {
                    ContentUnavailableView("No takes yet", systemImage: "waveform", description: Text("Press the red dot to record one."))
                }
            }
            .navigationTitle("Takes")
            .navigationDestination(for: String.self) { TakeScreen(takeID: $0) }
            .recButton()
        }
    }
}
