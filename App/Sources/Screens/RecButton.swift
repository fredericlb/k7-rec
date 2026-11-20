// The rec button beside the tab bar: a tap starts a take in place; while one runs its glass takes the input
// level's colour, its dot pulses and a tap opens the take's panel. Choices in docs/app.md, "Screens".
import SwiftUI

struct RecButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let size: CGFloat
    @State private var dim = false
    /// The level on the decibel scale, smoothed like a meter's needle.
    @State private var meter = 0.0

    var body: some View {
        Button {
            if model.recording { model.recorderOpen = true } else { Task { await model.startTake(song: model.songForTake) } }
        } label: {
            ZStack {
                Circle().strokeBorder(k7.record, lineWidth: 2.2).frame(width: 30, height: 30)
                Circle().fill(k7.record).frame(width: 12.5, height: 12.5).opacity(pulsing && dim ? 0.35 : 1)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tint).interactive(), in: .circle)
        .accessibilityLabel(model.recording ? "Take running" : "Record a take")
        .accessibilityHint(model.recording ? "Shows the take's controls" : "Starts recording here")
        .contextMenu { Button("Metronome", systemImage: "metronome") { model.recorderOpen = true } }
        .task(id: model.recording) { await followLevel() }
        .onChange(of: pulsing, initial: true) { _, on in
            withTransaction(Transaction(animation: nil)) { dim = false }
            if on { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true } }
        }
    }

    /// The input level as a colour over the glass, from the smoothed position; always a colour, clear at silence,
    /// so the tint is never removed and put back, which would jump instead of fading.
    private var tint: Color {
        let c = LevelMeter.tint(at: meter)
        return Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    /// While a take runs, eases the meter toward the level every 50 ms and animates each step, so the tint
    /// glides; a rest or a stop lets it fade out.
    private func followLevel() async {
        while model.recording, !Task.isCancelled {
            let target = model.recorder.paused ? 0 : LevelMeter.position(model.recorder.level)
            let next = LevelMeter.follow(meter, toward: target)
            withAnimation(.linear(duration: 0.05)) { meter = next }
            try? await Task.sleep(for: .milliseconds(50))
        }
        withAnimation(.easeOut(duration: 0.4)) { meter = 0 }
    }

    /// The dot pulses while a take runs behind a closed panel, so recording is never invisible.
    private var pulsing: Bool { model.recording && !model.recorderOpen && !reduceMotion }
}
