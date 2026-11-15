// One song: a header (back is the nav bar's, then play, title, menu) over a row of tabs, Info last and pinned right.
// What a reader gets wrong: the screen reads the live song by id, since the pushed value is a snapshot.
import SwiftUI
import UniformTypeIdentifiers

enum SongTab: String, CaseIterable {
    case chords = "Chords", diagrams = "Diagrams", lyrics = "Lyrics", tab = "Tab", sheets = "Sheets", info = "Info"
}

struct SongScreen: View {
    @Environment(AppModel.self) private var model
    let song: Song
    @State private var selected: SongTab?
    @State private var wave = Wave(samples: [], duration: 0)
    @State private var active: Int?
    @State private var menuOpen = false
    @State private var editing: TextKind?
    @State private var pickingSheet = false
    @State private var pickingLRC = false
    private var live: Song { model.library.songs.first { $0.id == song.id } ?? song }
    private var playID: String { "song:" + song.id }
    private var playing: Bool { model.player.loadedID == playID && model.player.isPlaying }
    private var semitones: Int { model.prefs.transpose(of: song.id) }

    private var tabs: [SongTab] { SongTabs.available(live) }
    private var current: SongTab { selected.flatMap { $0 == .info || tabs.contains($0) ? $0 : nil } ?? SongTabs.opening(live) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let url = live.audioURL, !wave.samples.isEmpty {
                WaveformView(
                    samples: wave.samples, duration: wave.duration, playing: playing, position: { model.player.position },
                    onSeek: { model.seek(id: playID, url: url, to: $0) })
                    .padding(.horizontal)
            }
            HStack {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(tabs, id: \.self) { tabButton($0).id($0) } }
                    }
                    .onChange(of: current) { _, tab in withAnimation { proxy.scrollTo(tab) } }
                    .onAppear { proxy.scrollTo(current) }
                }
                tabButton(.info, icon: "info.circle")
            }
            .padding(.horizontal)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let t = DebugLaunch.tab { selected = t }
            if let at = DebugLaunch.seek, let url = live.audioURL { model.seek(id: playID, url: url, to: at); refreshActive() }
            menuOpen = DebugLaunch.menu
            wave = await model.library.wave(of: live)
        }
        .task(id: playing) { await follow() }
        .onChange(of: current) { refreshActive() }
        .sheet(item: $editing) { kind in TextEditorSheet(song: live, kind: kind) }
        .fileImporter(isPresented: $pickingSheet, allowedContentTypes: [.pdf, .image]) { result in
            if case .success(let url) = result { Task { await report(await model.library.addSheet(from: url, to: live)) } }
        }
        .fileImporter(isPresented: $pickingLRC, allowedContentTypes: [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]) { result in
            if case .success(let url) = result { Task { await importLRC(url) } }
        }
    }

    private var header: some View {
        HStack {
            Button { if let url = live.audioURL { model.togglePlay(id: playID, url: url) } } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(playing ? "Pause" : "Play")
            .disabled(live.audioURL == nil)
            Text(live.title).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
            Button { menuOpen = true } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                .accessibilityLabel("Song menu")
                .popover(isPresented: $menuOpen) {
                    SongMenu(
                        song: live,
                        edit: { kind in menuOpen = false; editing = kind },
                        addSheet: { menuOpen = false; pickingSheet = true },
                        importLRC: { menuOpen = false; pickingLRC = true },
                        record: { menuOpen = false; Task { await model.startTake(song: live) } })
                        .presentationCompactAdaptation(.popover)
                }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private func tabButton(_ tab: SongTab, icon: String? = nil) -> some View {
        Button { selected = tab } label: {
            Group { if let icon { Image(systemName: icon) } else { Text(tab.rawValue) } }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(current == tab ? Color.accentColor.opacity(0.2) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
    }

    @ViewBuilder private var content: some View {
        switch current {
        case .chords: ChordsTab(text: live.chords, semitones: semitones, active: active, onTap: seek)
        case .lyrics: LyricsTab(text: live.lyrics, active: active, onTap: seek)
        case .tab: TabTab(text: live.tab)
        case .sheets: SheetsTab(song: live)
        case .diagrams: DiagramsTab(chords: SongText.diagramChords(chords: live.chords, lyrics: live.lyrics, semitones: semitones))
        case .info: InfoTab(song: live)
        }
    }

    private var followedText: String { current == .chords ? live.chords : live.lyrics }

    private func refreshActive() {
        let line = model.player.loadedID == playID ? SongText.activeLine(followedText, at: model.player.position) : nil
        if line != active { active = line }
    }

    private func follow() async {
        refreshActive()
        while playing, !Task.isCancelled {
            refreshActive()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func seek(line: Int) {
        guard let url = live.audioURL, let t = SongText.seekTime(line: line, in: followedText, lead: model.prefs.lyricsLead) else { return }
        model.seek(id: playID, url: url, to: t)
        if !playing { model.player.toggle() }
        refreshActive()
    }

    private func report(_ failure: String?) async { if let failure { model.notice = failure } }

    private func importLRC(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let lrc = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            model.notice = "That file could not be read."
            return
        }
        switch SongText.timedLyrics(live.lyrics, lrc: lrc) {
        case .failure(let e): model.notice = e.message
        case .success(let r):
            await report(await model.library.saveLyrics(r.text, for: live))
            if model.notice == nil { model.notice = "Timed \(r.placed) of \(r.total) lines." }
        }
    }
}

/// Which tabs a song shows and which one it opens on.
enum SongTabs {
    static func available(_ song: Song) -> [SongTab] {
        var out: [SongTab] = []
        if song.hasChords { out.append(.chords) }
        if song.hasLyrics { out.append(.lyrics) }
        if song.hasSheets { out.append(.sheets) }
        if song.hasTab { out.append(.tab) }
        let hasChords = !SongText.diagramChords(chords: song.chords, lyrics: song.lyrics, semitones: 0).isEmpty
        if hasChords { out.insert(.diagrams, at: min(1, out.count)) }
        return out
    }

    /// Chords, else lyrics, else sheets, else tab; Info only when the song has none.
    static func opening(_ song: Song) -> SongTab { available(song).first { $0 != .diagrams } ?? .info }
}
