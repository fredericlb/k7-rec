// The ⋮ popover: the date, the metronome, the transposition and the buttons that add texts and sheets.
// What a reader gets wrong: it is a popover, not a menu, so a control is used in place; the click lives in the model.
import SwiftUI

struct SongMenu: View {
    @Environment(AppModel.self) private var model
    let song: Song
    let edit: (TextKind) -> Void
    let addSheet: () -> Void
    let importLRC: () -> Void
    let record: () -> Void

    var body: some View {
        let semitones = model.prefs.transpose(of: song.id)
        VStack(alignment: .leading, spacing: 14) {
            Text("Added \(song.added.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
            HStack {
                Label("Metronome", systemImage: "metronome")
                Spacer()
                stepper(minus: { model.metronome.step(-1) }, plus: { model.metronome.step(1) }, label: "\(Int(model.metronome.bpm)) bpm",
                        minusLabel: "Slower", plusLabel: "Faster")
                Button { model.metronome.toggle() } label: { Image(systemName: model.metronome.running ? "stop.fill" : "play.fill").target() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(model.metronome.running ? "Stop metronome" : "Start metronome")
            }
            HStack {
                Label("Transpose", systemImage: "plusminus")
                Spacer()
                stepper(minus: { model.prefs.setTranspose(semitones - 1, of: song.id) }, plus: { model.prefs.setTranspose(semitones + 1, of: song.id) },
                        label: semitones > 0 ? "+\(semitones)" : "\(semitones)", minusLabel: "Transpose down", plusLabel: "Transpose up")
                Button("Reset") { model.prefs.setTranspose(0, of: song.id) }.disabled(semitones == 0)
            }
            Divider()
            ForEach(TextKind.allCases) { kind in
                Button(has(kind) ? "Edit \(kind.title.lowercased())" : "Add \(kind.title.lowercased())", systemImage: "text.alignleft") { edit(kind) }
            }
            Button("Import timing from an LRC file", systemImage: "clock") { importLRC() }.disabled(!song.hasLyrics)
            Button("Add a sheet", systemImage: "doc.badge.plus") { addSheet() }
            Button("Record a take", systemImage: "record.circle") { record() }
        }
        .padding()
        .frame(minWidth: 280, idealWidth: 360, maxWidth: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func has(_ kind: TextKind) -> Bool {
        switch kind {
        case .lyrics: song.hasLyrics
        case .chords: song.hasChords
        case .tabs: song.hasTab
        }
    }

    private func stepper(minus: @escaping () -> Void, plus: @escaping () -> Void, label: String, minusLabel: String, plusLabel: String) -> some View {
        HStack(spacing: 6) {
            Button(action: minus) { Image(systemName: "minus").target() }.buttonStyle(.bordered).accessibilityLabel(minusLabel)
            Text(label).monospacedDigit().fixedSize().frame(minWidth: 70)
            Button(action: plus) { Image(systemName: "plus").target() }.buttonStyle(.bordered).accessibilityLabel(plusLabel)
        }
    }
}
