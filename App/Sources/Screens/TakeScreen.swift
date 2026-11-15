// One take: its waveform, play, rename and delete.
import SwiftUI

struct TakeScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let takeID: String
    @State private var take: Take?
    @State private var renaming = false
    @State private var deleting = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 16) {
            if let take {
                Text(take.date.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                WaveformView(
                    samples: take.envelope, duration: take.duration, playing: playing, position: { model.player.position },
                    onSeek: { seconds in if let url = take.audioURL { model.seek(id: take.id, url: url, to: seconds) } })
                Button { if let url = take.audioURL { model.togglePlay(id: take.id, url: url) } } label: {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 56))
                }
                Text(String(format: "%d:%02d", Int(take.duration) / 60, Int(take.duration) % 60)).monospacedDigit()
            } else {
                ProgressView()
            }
            Spacer()
        }
        .padding()
        .navigationTitle(take?.title ?? "Take")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Rename", systemImage: "pencil") { draft = take?.title ?? ""; renaming = true }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
            } label: { Image(systemName: "ellipsis") }
        }
        .alert("Rename take", isPresented: $renaming) {
            TextField("Title", text: $draft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { Task { await rename() } }
        }
        .confirmationDialog("Delete this take?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await remove() } }
        }
        .task { take = await model.recorder.take(id: takeID) }
    }

    private var playing: Bool { model.player.loadedID == takeID && model.player.isPlaying }

    private func rename() async {
        await model.recorder.rename(id: takeID, title: draft)
        take = await model.recorder.take(id: takeID)
    }

    private func remove() async {
        if model.player.loadedID == takeID { model.player.unload() }
        await model.recorder.delete(id: takeID)
        dismiss()
    }
}
