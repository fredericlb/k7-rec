// One take: its waveform, play, rename and delete, then its moments and markers (Take/).
// What a reader gets wrong: detection is a button on each visit, never remembered; a moment plays its own span.
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let take, let moments { content(take, moments) } else { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding()
        }
        .navigationTitle(take?.title ?? "Take")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
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
            Button("Delete the take, its moments and markers", role: .destructive) { Task { await remove() } }
        }
        .task {
            take = await model.recorder.take(id: takeID)
            if let take { moments = TakeMoments(take: take, keeper: model.moments); await moments?.load() }
        }
    }

    @ViewBuilder
    private func content(_ take: Take, _ moments: TakeMoments) -> some View {
        Text(take.date.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
        WaveformView(
            samples: take.envelope, duration: take.duration, playing: playing, position: { model.player.position },
            onSeek: { seconds in if let url = take.audioURL { model.seek(id: take.id, url: url, to: seconds) } },
            marks: WaveformMarks(
                duration: take.duration, floor: moments.detecting ? moments.sift.floor : nil,
                found: moments.found.map { $0.startSec...$0.endSec }, saved: moments.saved.map(\.span), pins: moments.pins.map(\.at)))
        HStack(spacing: 20) {
            Button { if let url = take.audioURL { model.togglePlay(id: take.id, url: url) } } label: {
                Image(systemName: playing && model.player.range == nil ? "pause.circle.fill" : "play.circle.fill").font(.largeTitle)
            }
            .accessibilityLabel(playing && model.player.range == nil ? "Pause" : "Play")
            Text(clock(take.duration)).monospacedDigit()
        }
        HStack(spacing: 12) {
            Button { draft = ""; prompt = .newPin } label: { Label("Marker", systemImage: "mappin").lineLimit(1) }.buttonStyle(.bordered)
            Toggle("Detect moments", isOn: Binding(get: { moments.detecting }, set: { moments.setDetecting($0) }))
                .toggleStyle(.button).lineLimit(1).fixedSize().accessibilityIdentifier("detect")
        }
        if moments.detecting {
            DetectPanel(
                moments: moments, playing: { isPlaying($0, take) },
                play: { span in if let url = take.audioURL { model.playSpan(id: take.id, url: url, span: span, loops: false) } },
                save: { m in draft = TakeMoments.defaultTitle(at: m.startSec); prompt = .saveMoment(m) })
        }
        if !moments.saved.isEmpty {
            Text("Moments").font(.headline)
            SavedMomentRows(
                moments: moments.saved, playing: { isPlaying($0, take) },
                play: { m in if let url = take.audioURL { model.playSpan(id: take.id, url: url, span: m.span, loops: true) } },
                rename: { draft = $0.title; prompt = .renameMoment($0) }, delete: { m in Task { await moments.delete(m) } })
        }
        if !moments.pins.isEmpty {
            Text("Markers").font(.headline)
            PinRows(
                pins: moments.pins, seek: { p in if let url = take.audioURL { model.seek(id: take.id, url: url, to: p.at) } },
                rename: { draft = $0.note; prompt = .renamePin($0) }, delete: { p in Task { await moments.delete(p) } })
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
