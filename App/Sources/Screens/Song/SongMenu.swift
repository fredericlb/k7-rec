// The ⋮ popover: the date and the buttons that add texts and sheets, fetch lyrics and split stems.
// What a reader gets wrong: it is a popover on the iPhone, so a control is used in place; the Mac lists the same actions in a Menu.
import SwiftUI

struct SongMenu: View {
    let song: Song
    let edit: (TextKind) -> Void
    let addSheet: () -> Void
    let importLRC: () -> Void
    let downloadLyrics: () -> Void
    let stems: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Added \(song.added.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
            Divider()
            SongActions(song: song, edit: edit, addSheet: addSheet, importLRC: importLRC, downloadLyrics: downloadLyrics, stems: stems)
        }
        .padding()
        .frame(minWidth: 280, idealWidth: 360, maxWidth: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The song's actions as buttons: the popover lays them out, a Mac menu lists them.
struct SongActions: View {
    @Environment(AppModel.self) private var model
    let song: Song
    let edit: (TextKind) -> Void
    let addSheet: () -> Void
    let importLRC: () -> Void
    let downloadLyrics: () -> Void
    let stems: () -> Void

    var body: some View {
        Group {
            ForEach(TextKind.allCases) { kind in
                Button(has(kind) ? "Edit \(kind.title.lowercased())" : "Add \(kind.title.lowercased())", systemImage: "text.alignleft") { edit(kind) }
            }
            Button("Import timing from an LRC file", systemImage: "clock") { importLRC() }.disabled(!song.hasLyrics)
            Button(song.hasLyrics ? "Download timing from LRCLIB" : "Download lyrics from LRCLIB", systemImage: "arrow.down.circle") { downloadLyrics() }
                .disabled(model.lyricsBusy)
            Button("Add a sheet", systemImage: "doc.badge.plus") { addSheet() }
            Button("Separate into stems", systemImage: "waveform.path") { stems() }.disabled(song.audioURL == nil)
        }
    }

    private func has(_ kind: TextKind) -> Bool {
        switch kind {
        case .lyrics: song.hasLyrics
        case .chords: song.hasChords
        case .tabs: song.hasTab
        }
    }
}
