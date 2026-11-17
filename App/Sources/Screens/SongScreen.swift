// One song: the nav bar holds back, play, title and the menu, over a row of tabs, Info last and pinned right.
// What a reader gets wrong: the screen reads the live song by id, since the pushed value is a snapshot.
import RehearsalText
import SwiftUI
import UniformTypeIdentifiers

enum SongTab: String, CaseIterable {
    case chords = "Chords", diagrams = "Diagrams", lyrics = "Lyrics", tab = "Tab", sheets = "Sheets", info = "Info"
}

/// Which file the song's one importer is asked for.
private enum PickKind { case sheet, lrc }

struct SongScreen: View {
    @Environment(AppModel.self) private var model
    let song: Song
    @State private var selected: SongTab?
    @State private var wave = Wave(samples: [], duration: 0)
    @State private var active: Int?
    @State private var menuOpen = false
    @State private var stemsOpen = false
    @State private var hasStems = false
    @State private var editing: TextKind?
    @State private var picking: PickKind?
    @State private var pickedKind: PickKind = .sheet
    private var live: Song { model.library.songs.first { $0.id == song.id } ?? song }
    private var playID: String { model.playID(of: live) }
    private var playing: Bool {
        model.player.loadedID == playID && model.player.isPlaying
    }
    private var semitones: Int { model.prefs.transpose(of: song.id) }

    private var tabs: [SongTab] { SongTabs.available(live) }
    private var current: SongTab { selected.flatMap { $0 == .info || tabs.contains($0) ? $0 : nil } ?? SongTabs.opening(live) }

    var body: some View {
        VStack(spacing: 0) {
            if let url = model.playURL(of: live), !wave.samples.isEmpty {
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
                if hasStems { versionSwitch }
                tabButton(.info, icon: "info.circle")
            }
            .padding(.horizontal)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { header }
        .popover(isPresented: $menuOpen, attachmentAnchor: .point(.topTrailing), arrowEdge: .top) {
            SongMenu(
                song: live,
                edit: { kind in menuOpen = false; editing = kind },
                addSheet: { menuOpen = false; picking = .sheet; pickedKind = .sheet },
                importLRC: { menuOpen = false; picking = .lrc; pickedKind = .lrc },
                downloadLyrics: { menuOpen = false; Task { await model.downloadLyrics(for: live) } },
                record: { menuOpen = false; Task { await model.startTake(song: live) } },
                stems: { menuOpen = false; stemsOpen = true })
                .presentationCompactAdaptation(.popover)
        }
        .task {
            if let t = DebugLaunch.tab { selected = t }
            if let at = DebugLaunch.seek, let url = model.playURL(of: live) { model.seek(id: playID, url: url, to: at); refreshActive() }
            menuOpen = DebugLaunch.menu
            hasStems = model.stems.existing(for: live) != nil
            wave = await model.library.wave(of: live)
        }
        .task(id: "\(playing)-\(current.rawValue)") { await follow() }
        .onChange(of: current) { refreshActive() }
        .onChange(of: stemsOpen) { hasStems = model.stems.existing(for: live) != nil }
        .sheet(isPresented: $stemsOpen) { StemsSheet(song: live) }
        .sheet(item: $editing) { kind in TextEditorSheet(song: live, kind: kind) }
        .fileImporter(
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            allowedContentTypes: picking == .lrc ? [UTType(filenameExtension: "lrc") ?? .plainText, .plainText] : [.pdf, .image]
        ) { result in
            let kind = pickedKind
            guard case .success(let url) = result else { return }
            Task { if kind == .lrc { await importLRC(url) } else { await report(await model.library.addSheet(from: url, to: live)) } }
        }
    }

    @ToolbarContentBuilder private var header: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                if let url = model.playURL(of: live) { model.togglePlay(id: playID, url: url) }
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(playing ? "Pause" : "Play")
            .disabled(model.playURL(of: live) == nil)
        }
        ToolbarItem(placement: .principal) {
            Text(live.title).font(.headline).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
        ToolbarItem(placement: .topBarTrailing) {
            #if targetEnvironment(macCatalyst)
            // A popover anchored in the bar does not open under Catalyst; the Mac gets a menu of the same actions.
            Menu { actions() } label: { Image(systemName: "ellipsis").target() }
                .accessibilityLabel("Song menu")
            #else
            Button { menuOpen = true } label: { Image(systemName: "ellipsis").target() }
                .accessibilityLabel("Song menu")
            #endif
        }
    }

    private func actions() -> SongActions {
        SongActions(
            song: live,
            edit: { editing = $0 },
            addSheet: { picking = .sheet; pickedKind = .sheet },
            importLRC: { picking = .lrc; pickedKind = .lrc },
            downloadLyrics: { Task { await model.downloadLyrics(for: live) } },
            record: { Task { await model.startTake(song: live) } },
            stems: { stemsOpen = true })
    }

    /// Full song or instrumental, left of Info; it exists once the song has stems.
    private var versionSwitch: some View {
        let instrumental = model.playsInstrumental(live)
        return Button { Task { await model.switchVersion(of: live) } } label: {
            Group {
                if model.mixing { ProgressView() } else { Image(systemName: instrumental ? "mic.slash.fill" : "mic.fill") }
            }
            .frame(minWidth: 44, minHeight: 44)
            .background(instrumental ? Color.accentColor.opacity(0.2) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.mixing)
        .accessibilityLabel(instrumental ? "Play the full song" : "Play the instrumental")
        .accessibilityIdentifier("versionSwitch")
    }

    private func tabButton(_ tab: SongTab, icon: String? = nil) -> some View {
        Button { selected = tab } label: {
            Group { if let icon { Image(systemName: icon) } else { Text(tab.rawValue) } }
                .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
                .background(current == tab ? Color.accentColor.opacity(0.2) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(current == tab ? .isSelected : [])
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

    private func refreshActive(_ timing: [LineTime]? = nil) {
        let line = model.player.loadedID == playID ? LyricsTiming.lineAt(timing ?? LyricsTiming.byLine(followedText), seconds: model.player.position) : nil
        if line != active { active = line }
    }

    private func follow() async {
        refreshActive()
        let timing = LyricsTiming.byLine(followedText)
        while playing, !Task.isCancelled {
            refreshActive(timing)
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func seek(line: Int) {
        guard let url = model.playURL(of: live), let t = SongText.seekTime(line: line, in: followedText, lead: model.prefs.lyricsLead) else { return }
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
        if song.hasDiagrams { out.insert(.diagrams, at: min(1, out.count)) }
        return out
    }

    /// Chords, else lyrics, else sheets, else tab; Info only when the song has none.
    static func opening(_ song: Song) -> SongTab { available(song).first { $0 != .diagrams } ?? .info }
}
