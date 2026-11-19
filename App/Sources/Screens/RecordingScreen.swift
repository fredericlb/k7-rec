// The take panel, a sheet from the rec button: the running take with its live waveform, or a way to start one, and the metronome.
// What a reader gets wrong: a call pauses the take, it never ends it; Resume continues the same take.
import SwiftUI

struct RecordingScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.recording { running } else { idle }
            }
            .navigationTitle("Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.recorderOpen = false } } }
        }
    }

    private var idle: some View {
        VStack(spacing: 16) {
            Image(systemName: "record.circle").font(.system(size: 56)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("No take is running").foregroundStyle(.secondary)
            Button { Task { await model.startTake() } } label: { Label("Start recording", systemImage: "circle.fill") }
                .buttonStyle(.borderedProminent).tint(.red)
            metronome.padding(.top, 24)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The click to play along to; it lives in the model, so it keeps going while a take starts or stops.
    private var metronome: some View {
        HStack {
            Label("Metronome", systemImage: "metronome")
            Spacer()
            StepperControl(
                label: "\(Int(model.metronome.bpm)) bpm", minusLabel: "Slower", plusLabel: "Faster",
                minus: { model.metronome.step(-1) }, plus: { model.metronome.step(1) })
            Button { model.metronome.toggle() } label: { Image(systemName: model.metronome.running ? "stop.fill" : "play.fill").target() }
                .buttonStyle(.bordered)
                .accessibilityLabel(model.metronome.running ? "Stop metronome" : "Start metronome")
        }
    }

    private var running: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            ScrollView {
                VStack(spacing: 20) {
                    if let why = reason { Text(why).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).accessibilityIdentifier("pauseReason") }
                    Text(format(model.recorder.elapsed)).font(.system(size: 56, weight: .light)).monospacedDigit()
                    ProgressView(value: min(1, model.recorder.level)).accessibilityLabel("Input level")
                    ZStack {
                        WaveformBars(samples: model.recorder.liveSamples).equatable()
                        WaveformMarks(duration: LiveTake.windowSeconds, start: model.recorder.liveWindowStart, found: model.recorder.highlights.map(\.span)).equatable()
                    }
                    .frame(height: 120).accessibilityHidden(true)
                    metronome
                    controls
                    highlights
                }
                .padding()
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 32) {
            Button {
                if model.recorder.paused { Task { await model.resumeTake() } } else { model.recorder.pause() }
            } label: {
                if model.recorder.pauseCause == .user || !model.recorder.paused {
                    Image(systemName: model.recorder.paused ? "play.fill" : "pause.fill").font(.title)
                } else { Text("Resume").bold() }
            }
            .target().frame(minWidth: 56, minHeight: 56)
            .accessibilityLabel(model.recorder.paused ? "Resume take" : "Pause take")
            Button { Task { await model.stopTake() } } label: { Image(systemName: "stop.fill").font(.title) }
                .target().frame(minWidth: 56, minHeight: 56)
                .accessibilityLabel("Stop take")
        }
    }

    /// The moments found so far; playing one rests the take, Resume carries on recording.
    private var highlights: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(model.recorder.highlights.count) highlights", systemImage: "scope").font(.headline).monospacedDigit()
                .accessibilityIdentifier("liveMoments")
            ForEach(model.recorder.highlights) { h in
                HStack(spacing: 12) {
                    Button { model.listen(to: h) } label: {
                        Image(systemName: heard(h) ? "stop.fill" : "play.fill").target()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(heard(h) ? "Stop highlight" : "Play highlight, pauses the recording")
                    WaveformBars(samples: h.samples).equatable().frame(height: 44).accessibilityHidden(true)
                    Text(format(h.span.lowerBound)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heard(_ h: Highlight) -> Bool { model.listeningTo == h.id && model.player.isPlaying }

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
