// The rec button at the top right of every screen: a tap starts a take in place; while one runs it is
// the input-level LED and opens the take's panel. Choices in docs/app.md, "Screens".
import SwiftUI

struct RecButton: View {
    @Environment(AppModel.self) private var model
    /// The song a take started here belongs to; nil records a take with no song.
    var song: Song?

    var body: some View {
        Button {
            if model.recording { model.recorderOpen = true } else { Task { await model.startTake(song: song) } }
        } label: {
            if model.recording { led } else { Image(systemName: "record.circle").foregroundStyle(.red).target() }
        }
        .accessibilityLabel(model.recording ? "Take running" : "Record a take")
        .accessibilityHint(model.recording ? "Shows the take's controls" : "Starts recording here")
        .contextMenu { Button("Metronome", systemImage: "metronome") { model.recorderOpen = true } }
    }

    /// One LED lit by the input level, ringed red so a silent take still reads as recording.
    private var led: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let c = LevelLED.rgb(model.recorder.paused ? 0 : model.recorder.level)
            Circle()
                .fill(Color(red: c.red, green: c.green, blue: c.blue))
                .overlay(Circle().strokeBorder(.red, lineWidth: 2))
                .frame(width: 22, height: 22)
                .target()
        }
    }
}

extension View {
    /// Puts the rec button at the top right of a screen's navigation bar.
    func recButton(song: Song? = nil) -> some View {
        toolbar { ToolbarItem(placement: .topBarTrailing) { RecButton(song: song) } }
    }
}
