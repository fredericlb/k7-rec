// The Takes list, newest first; tapping a row plays it through the player seam.
import SwiftUI

struct TakesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var playing: String?

    var body: some View {
        NavigationStack {
            List(model.recorder.takes) { take in
                Button {
                    if playing == take.id { model.player.stop(); playing = nil } else { model.player.play(id: take.id); playing = take.id }
                } label: {
                    HStack {
                        Image(systemName: playing == take.id ? "stop.fill" : "play.fill")
                        VStack(alignment: .leading) {
                            Text(take.songTitle)
                            Text(take.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%d:%02d", Int(take.duration) / 60, Int(take.duration) % 60)).monospacedDigit()
                    }
                }
            }
            .navigationTitle("Takes")
        }
    }
}
