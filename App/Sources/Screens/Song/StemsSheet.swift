// The stems sheet: separate a song into drums, bass, other and vocals, then play them with a mute, a solo and a level each.
// What a reader gets wrong: the work runs in the foreground and the sheet is its only view, so closing it cancels.
import RehearsalStems
import SwiftUI

struct StemsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let song: Song
    @State private var session: StemSession?
    @State private var progress: Double?
    @State private var working: Task<Void, Never>?
    @State private var scrub: Double?

    var body: some View {
        NavigationStack {
            Group {
                if let session { mixer(session) } else if let progress { busy(progress) } else { start }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Stems")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { close() } }
                if session != nil { ToolbarItem(placement: .destructiveAction) { Button("Remove", role: .destructive, action: remove) } }
            }
        }
        .task { open() }
        .onDisappear { close(dismissing: false) }
    }

    private var start: some View {
        let hasModel = model.stems.hasModel
        return VStack(spacing: 16) {
            Image(systemName: "waveform.path").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(hasModel
                 ? "Split \(song.title) into drums, bass, other and vocals. It takes a few minutes; keep the app open."
                 : "No separation model is installed. Put StemSeparator.mlpackage in the Models folder of K7 REC, in the Files app.")
                .multilineTextAlignment(.center)
            if hasModel, let note = StemAdvice.memoryNote() { Text(note).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            Button("Separate", systemImage: "scissors") { separate() }
                .buttonStyle(.borderedProminent).disabled(!hasModel || song.audioURL == nil)
        }
    }

    private func busy(_ fraction: Double) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: fraction) { Text("Separating") }
            Text(fraction.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit().foregroundStyle(.secondary)
            Button("Cancel", role: .cancel) { working?.cancel() }.buttonStyle(.bordered)
        }
    }

    private func mixer(_ s: StemSession) -> some View {
        VStack(spacing: 18) {
            ForEach(Stem.allCases) { stem in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stem.title).font(.headline)
                        Spacer()
                        toggle("M", on: s.mix.muted.contains(stem), label: "Mute \(stem.title)") { s.mix.toggleMute(stem) }
                        toggle("S", on: s.mix.solo.contains(stem), label: "Solo \(stem.title)") { s.mix.toggleSolo(stem) }
                    }
                    Slider(value: Binding(get: { Double(s.mix.level(of: stem)) }, set: { s.mix.setLevel(Float($0), of: stem) }), in: 0...1)
                        .accessibilityLabel("\(stem.title) level")
                }
            }
            HStack {
                Button { s.toggle() } label: { Image(systemName: s.isPlaying ? "pause.fill" : "play.fill").target() }
                    .buttonStyle(.bordered).accessibilityLabel(s.isPlaying ? "Pause" : "Play")
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Slider(value: Binding(get: { scrub ?? s.position }, set: { scrub = $0 }), in: 0...max(s.duration, 1)) { editing in
                        if !editing, let to = scrub { s.seek(to: to); scrub = nil }
                    }
                    .accessibilityLabel("Position")
                }
            }
        }
    }

    private func toggle(_ letter: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(letter).font(.body.bold()).target() }
            .buttonStyle(.bordered).tint(on ? .accentColor : .secondary).accessibilityLabel(label)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func open() {
        guard session == nil, let urls = model.stems.existing(for: song) else { return }
        session = try? StemSession(urls: urls)
        session?.semitones = model.prefs.transpose(of: song.id)
        session?.onIdle = { model.restSession() }
    }

    private func separate() {
        progress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        working = Task {
            let failure = await model.stems.separate(song) { fraction in Task { @MainActor in if progress != nil { progress = fraction } } }
            progress = nil
            UIApplication.shared.isIdleTimerDisabled = false
            if let failure { model.notice = failure }
            open()
        }
    }

    private func remove() {
        close(dismissing: false)
        model.stems.remove(for: song)
        session = nil
    }

    private func close(dismissing: Bool = true) {
        working?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        session?.stop()
        if dismissing { dismiss() }
    }
}
