// A plain-text editor for the lyrics, the chords or the tab of a song; emptying the text removes the file.
// On iPad and the Mac it takes 80% of the window each way; on iPhone a sheet is the screen's width anyway.
import SwiftUI
import UIKit

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
        .presentationSizing(WindowFraction(fraction: 0.8))
    }

    private var current: String {
        switch kind {
        case .lyrics: song.lyrics
        case .chords: song.chords
        case .tabs: song.tab
        }
    }

    private func save() async {
        let failure: String?
        switch kind {
        case .lyrics: failure = await model.library.saveLyrics(text, for: song)
        case .chords: failure = await model.library.saveChords(text, for: song)
        case .tabs: failure = await model.library.saveText(kind, text, for: song)
        }
        if let failure { model.notice = failure } else { dismiss() }
    }
}

/// A sheet a fraction of its window's size each way; the sizing API is given no container, so the window is read.
struct WindowFraction: PresentationSizing {
    let fraction: CGFloat

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        let window = MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.bounds.size
        }
        guard let window else { return .unspecified }
        return ProposedViewSize(width: window.width * fraction, height: window.height * fraction)
    }
}
