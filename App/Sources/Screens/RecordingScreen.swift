// The take panel, a sheet from the rec button: the running take (clock, level, live waveform with its highlight
// spans, transport) or a way to start one; the metronome is a menu from its header. A call pauses a take, never ends it.
import SwiftUI

struct RecordingScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var metronomeOpen = false
    private var metrics: Metrics { Metrics(sizeClass) }

    var body: some View {
        VStack(spacing: 22) {
            header
            if model.recording { running } else { idle }
        }
        .padding(.horizontal, metrics.wide ? 28 : 20).padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationBackground { LinearGradient(colors: [k7.sheetTop, k7.sheetBottom], startPoint: .top, endPoint: .bottom) }
        .presentationCornerRadius(K7Radius.bar)
        .presentationDetents(metrics.wide ? [.large] : [.height(560), .large])
    }

    private var header: some View {
        ZStack {
            Text("Recording").font(.headline.weight(.bold))
            HStack {
                Button { metronomeOpen = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "metronome").font(.system(size: 18))
                        if model.metronome.running { Text("\(Int(model.metronome.bpm))").monospacedDigit() }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.metronome.running ? k7.onAccent : k7.text)
                    .padding(.horizontal, 12).frame(minWidth: K7Size.touch, minHeight: K7Size.touch)
                    .background(model.metronome.running ? k7.accent : k7.fillControl, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.metronome.running ? "Metronome, on at \(Int(model.metronome.bpm)) bpm" : "Metronome, off")
                .accessibilityIdentifier("metronomeButton")
                .popover(isPresented: $metronomeOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    metronome.presentationCompactAdaptation(.popover).presentationBackground(k7.menu)
                }
                Spacer()
                Button("Done") { model.recorderOpen = false }
                    .font(.system(size: 15, weight: .semibold))
                    .buttonStyle(.glass)
            }
        }
        .frame(minHeight: K7Size.touch)
    }

    /// The click to play along to; it lives in the model, so it keeps going while a take starts or stops.
    private var metronome: some View {
        VStack(spacing: 0) {
            Toggle("Metronome", isOn: Binding(get: { model.metronome.running }, set: { _ in model.metronome.toggle() }))
                .frame(minHeight: 54)
                .accessibilityIdentifier("metronomeSwitch")
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            HStack {
                Text("Tempo")
                Spacer()
                StepperControl(
                    label: "\(Int(model.metronome.bpm)) bpm", minusLabel: "Slower", plusLabel: "Faster",
                    minus: { model.metronome.step(-1) }, plus: { model.metronome.step(1) })
            }
            .frame(minHeight: 58)
        }
        .padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 4)
        .frame(width: 300)
    }

    private var idle: some View {
        EmptyState(symbol: "record.circle", title: "No take is running") {
            Button { Task { await model.startTake(song: model.songForTake) } } label: {
                HStack(spacing: 10) {
                    Circle().fill(k7.onDanger).frame(width: 18, height: 18)
                    Text("Start recording")
                }
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(k7.onDanger)
                .padding(.leading, 20).padding(.trailing, 26).frame(height: 52)
                .background(k7.danger, in: Capsule())
                .shadow(color: k7.danger.opacity(0.4), radius: 12, y: 8)
            }
            .buttonStyle(.plain)
        }
        .frame(maxHeight: 360)
    }

    private var running: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            VStack(spacing: 18) {
                if let why = reason {
                    Text(why).font(.callout).foregroundStyle(k7.textSecondary).multilineTextAlignment(.center).accessibilityIdentifier("pauseReason")
                }
                Text(clock(model.recorder.elapsed)).font(.system(size: 76, weight: .light)).tracking(-1).monospacedDigit()
                ProgressView(value: LevelMeter.position(model.recorder.paused ? 0 : model.recorder.level))
                    .tint(k7.accent)
                    .accessibilityLabel("Input level")
                LiveWell(
                    samples: model.recorder.liveSamples, start: model.recorder.liveWindowStart, paused: model.recorder.paused,
                    highlights: model.recorder.highlights, heard: heardHighlight, range: model.player.range,
                    position: model.player.position, listen: { model.listen(to: $0) })
                    .frame(height: metrics.well(120))
                if let h = heardHighlight {
                    HStack {
                        Text("Playing highlight · \(clock(h.span.lowerBound)) – \(clock(h.span.upperBound))").foregroundStyle(k7.highlight)
                        Spacer()
                        Text("Recording paused").foregroundStyle(k7.textSecondary)
                    }
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
                controls.padding(.top, 4)
            }
            .padding(.bottom, metrics.wide ? 30 : 44)
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            if heardHighlight != nil || (model.recorder.paused && model.recorder.pauseCause != .user) {
                Button { Task { await model.resumeTake() } } label: {
                    HStack(spacing: 10) {
                        Circle().fill(.white).frame(width: 16, height: 16)
                        Text("Resume")
                    }
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(k7.onAccent)
                    .padding(.leading, 24).padding(.trailing, 30).frame(height: 68)
                    .background(k7.accent, in: Capsule())
                    .shadow(color: k7.accent.opacity(0.4), radius: 11, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume take")
            } else {
                Button {
                    if model.recorder.paused { Task { await model.resumeTake() } } else { model.recorder.pause() }
                } label: {
                    Image(systemName: model.recorder.paused ? "play.fill" : "pause.fill").font(.system(size: 28))
                        .frame(width: 68, height: 68).fillControl(Circle()).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.recorder.paused ? "Resume take" : "Pause take")
            }
            Button { Task { await model.stopTake() } } label: {
                Image(systemName: "stop.fill").font(.system(size: 28)).foregroundStyle(k7.onDanger)
                    .frame(width: 68, height: 68).background(k7.danger, in: Circle())
                    .shadow(color: k7.danger.opacity(0.4), radius: 12, y: 8)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop take")
        }
    }

    private var heardHighlight: Highlight? {
        model.recorder.highlights.first { model.listeningTo == $0.id && model.player.isPlaying }
    }

    private var reason: String? {
        switch model.recorder.pauseCause {
        case .interrupted: "Paused by a call or another app. The take is kept."
        case .inputLost: "The microphone was lost. The take is kept."
        default: nil
        }
    }
}
