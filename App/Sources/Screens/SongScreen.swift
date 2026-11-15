// One song: a header (back is the nav bar's, then play, title, menu) over a row of tabs, Info last and pinned right.
import SwiftUI

enum SongTab: String, CaseIterable {
    case chords = "Chords", lyrics = "Lyrics", tab = "Tab", sheets = "Sheets", info = "Info"
}

struct SongScreen: View {
    @Environment(AppModel.self) private var model
    let song: Song
    @State private var selected: SongTab
    @State private var playing = false

    init(song: Song) {
        self.song = song
        _selected = State(initialValue: song.hasChords ? .chords : song.hasLyrics ? .lyrics : song.hasSheets ? .sheets : .info)
    }

    private var tabs: [SongTab] {
        SongTab.allCases.filter { t in
            switch t {
            case .chords: song.hasChords
            case .lyrics: song.hasLyrics
            case .tab: song.hasTab
            case .sheets: song.hasSheets
            case .info: false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                Text(song.title).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                Menu {
                    Text("Added \(song.added.formatted(date: .abbreviated, time: .omitted))")
                    Button("Metronome", systemImage: "metronome") {}
                    Button("Transpose", systemImage: "plusminus") {}
                    Button("Record a take", systemImage: "record.circle") { model.startTake(song: song) }
                } label: { Image(systemName: "ellipsis") }
            }
            .padding(.horizontal).padding(.vertical, 8)
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(tabs, id: \.self) { tabButton($0) } }
                }
                tabButton(.info, icon: "info.circle")
            }
            .padding(.horizontal)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tabButton(_ tab: SongTab, icon: String? = nil) -> some View {
        Button { selected = tab } label: {
            Group { if let icon { Image(systemName: icon) } else { Text(tab.rawValue) } }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected == tab ? Color.accentColor.opacity(0.2) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        switch selected {
        case .chords: ScrollView { Text(song.chords).font(.system(.body, design: .monospaced)).padding() }
        case .lyrics: ScrollView { Text(song.lyrics).padding() }
        case .info:
            Form {
                LabeledContent("Title", value: song.title)
                LabeledContent("Artist", value: song.artist.isEmpty ? "-" : song.artist)
            }
        default: ContentUnavailableView(selected.rawValue, systemImage: "doc.text", description: Text("Nothing to show yet."))
        }
    }
}
