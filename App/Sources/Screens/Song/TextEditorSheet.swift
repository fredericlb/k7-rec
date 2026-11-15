// A plain-text editor for the lyrics, the chords or the tab of a song; emptying the text removes the file.
import SwiftUI

struct TextEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let song: Song
    let kind: TextKind
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(.horizontal, 8)
                .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } } }
                }
        }
        .onAppear { text = current }
    }

    private var current: String {
        switch kind {
        case .lyrics: song.lyrics
        case .chords: song.chords
        case .tabs: song.tab
        }
    }

    private func save() async {
        let failure = kind == .lyrics ? await model.library.saveLyrics(text, for: song) : await model.library.saveText(kind, text, for: song)
        if let failure { model.notice = failure } else { dismiss() }
    }
}
