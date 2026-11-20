// One take: its waveform, play, rename and delete, then its highlights and markers (Take/).
// What a reader gets wrong: detection is a button on each visit, never remembered; a highlight plays its own span.
import SwiftUI

struct TakeScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let takeID: String
    @State private var take: Take?
    @State private var moments: TakeMoments?
    @State private var renaming = false
    @State private var deleting = false
    @State private var prompt: TakePrompt?
    @State private var draft = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var metrics: Metrics { Metrics(sizeClass) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let take, let moments { content(take, moments) } else { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, metrics.margin).padding(.vertical, 6)
        }
        .screenBackground()
        .k7Header(take?.title ?? "Take", subtitle: take?.date.formatted(date: .complete, time: .shortened) ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename", systemImage: "pencil") { draft = take?.title ?? ""; renaming = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Take menu")
            }
        }
        .alert("Rename take", isPresented: $renaming) {
            TextField("Title", text: $draft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { Task { await rename() } }
        }
        .alert(prompt?.heading ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField("Name", text: $draft)
            Button("Cancel", role: .cancel) {}
            Button("OK") { if let p = prompt, let moments { Task { await answer(p, moments) } } }
        }
        .confirmationDialog("Delete this take?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete the take, its highlights and markers", role: .destructive) { Task { await remove() } }
        }
        .task {
            take = await model.recorder.take(id: takeID)
            if let take { moments = TakeMoments(take: take, keeper: model.moments); await moments?.load() }
        }
    }

    @ViewBuilder
    private func content(_ take: Take, _ moments: TakeMoments) -> some View {
        WaveformView(
            samples: take.envelope, duration: take.duration, playing: playing, position: { model.player.position },
            onSeek: { seconds in if let url = take.audioURL { model.seek(id: take.id, url: url, to: seconds) } },
            marks: WaveformMarks(
                duration: take.duration, floor: moments.detecting ? moments.sift.floor : nil,
                found: moments.found.map { $0.startSec...$0.endSec }, saved: moments.saved.map(\.span), pins: moments.pins.map(\.at)))
            .overlay { spans(take, moments) }
            .frame(height: metrics.well(160))
            .waveWell()
        HStack(spacing: 16) {
            Button { if let url = take.audioURL { model.togglePlay(id: take.id, url: url) } } label: {
                Image(systemName: playing && model.player.range == nil ? "pause.fill" : "play.fill").font(.title2)
                    .foregroundStyle(k7.onAccent).frame(width: 44, height: 44)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel(playing && model.player.range == nil ? "Pause" : "Play")
            Text(clock(take.duration)).font(.title2.weight(.medium)).monospacedDigit()
            Spacer(minLength: 0)
        }
        HStack(spacing: 10) {
            Button { draft = ""; prompt = .newPin } label: { Label("Marker", systemImage: "mappin").lineLimit(1).foregroundStyle(k7.accentSoft) }
                .buttonStyle(.glass).controlSize(.large)
            Toggle(isOn: Binding(get: { moments.detecting }, set: { moments.setDetecting($0) })) {
                Label("Detect moments", systemImage: "sparkles").lineLimit(1)
            }
            .toggleStyle(.button).buttonStyle(.glass).controlSize(.large).fixedSize().accessibilityIdentifier("detect")
        }
        if moments.detecting {
            DetectPanel(
                moments: moments, playing: { isPlaying($0, take) },
                play: { span in if let url = take.audioURL { model.playSpan(id: take.id, url: url, span: span, loops: false) } },
                save: { m in draft = TakeMoments.defaultTitle(at: m.startSec); prompt = .saveMoment(m) })
                .padding(20).card()
        }
        if !moments.saved.isEmpty {
            SectionTitle("Highlights").padding(.bottom, -10)
            SavedMomentRows(
                moments: moments.saved, playing: { isPlaying($0, take) },
                play: { m in if let url = take.audioURL { model.playSpan(id: take.id, url: url, span: m.span, loops: true) } },
                rename: { draft = $0.title; prompt = .renameMoment($0) }, delete: { m in Task { await moments.delete(m) } })
        }
        if !moments.pins.isEmpty {
            SectionTitle("Markers").padding(.bottom, -10)
            PinRows(
                pins: moments.pins, seek: { p in if let url = take.audioURL { model.seek(id: take.id, url: url, to: p.at) } },
                rename: { draft = $0.note; prompt = .renamePin($0) }, delete: { p in Task { await moments.delete(p) } })
        }
    }

    /// Each kept highlight as a button over its span of the waveform: a tap plays it in a loop, as its row does.
    private func spans(_ take: Take, _ moments: TakeMoments) -> some View {
        GeometryReader { geo in
            ForEach(moments.saved) { m in
                let x = take.duration > 0 ? m.start / take.duration * geo.size.width : 0
                let w = take.duration > 0 ? max(12, (m.end - m.start) / take.duration * geo.size.width) : 0
                Button { if let url = take.audioURL { model.playSpan(id: take.id, url: url, span: m.span, loops: true) } } label: {
                    Rectangle().fill(isPlaying(m.span, take) ? k7.highlightFillSelected : Color.clear)
                }
                .buttonStyle(.plain)
                .frame(width: w, height: geo.size.height)
                .offset(x: x)
                .accessibilityLabel("\(m.title), \(clock(m.start)) to \(clock(m.end))")
            }
        }
    }

    private var playing: Bool { model.player.loadedID == takeID && model.player.isPlaying }

    private func isPlaying(_ span: ClosedRange<TimeInterval>, _ take: Take) -> Bool { playing && model.player.range == span }

    private func answer(_ p: TakePrompt, _ moments: TakeMoments) async {
        switch p {
        case .saveMoment(let m): await moments.save(m, title: draft)
        case .renameMoment(let m): await moments.rename(m, to: draft)
        case .newPin: await moments.addPin(at: model.player.loadedID == takeID ? model.player.position : 0, note: draft)
        case .renamePin(let pin): await moments.rename(pin, to: draft)
        }
    }

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
