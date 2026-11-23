// One song: the bar holds back, the title and artist, the favourite star, play and the menu; under it the waveform, then the views
// as a glass switch, with Info and the instrumental switch at its right on iPad and the Mac, in the menu on iPhone.
// What a reader gets wrong: the screen reads the live song by id, since the pushed value is a snapshot.
import RehearsalText
import SwiftUI
import UniformTypeIdentifiers

enum SongTab: String, CaseIterable {
    case chords = "Chords", lyrics = "Lyrics", tab = "Tab", sheets = "Sheets", info = "Info"
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
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var metrics: Metrics { Metrics(sizeClass) }
    private var live: Song { model.library.songs.first { $0.id == song.id } ?? song }
    private var playID: String { model.playID(of: live) }
    private var playing: Bool {
        model.player.loadedID == playID && model.player.isPlaying
    }
    /// The chords' shift: the transposition, plus the capo on the piano (SongPrefs.shownSemitones).
    private var semitones: Int { model.prefs.shownSemitones(of: live) }

    private var tabs: [SongTab] { SongTabs.available(live) }
    private var current: SongTab { selected.flatMap { $0 == .info || tabs.contains($0) ? $0 : nil } ?? SongTabs.opening(live) }

    var body: some View {
        VStack(spacing: 14) {
            if let url = model.playURL(of: live), !wave.samples.isEmpty {
                WaveformView(
                    samples: wave.samples, duration: wave.duration, playing: playing, position: { model.player.position },
                    onSeek: { model.seek(id: playID, url: url, to: $0) })
                    .frame(height: metrics.well(116))
                    .waveWell()
                    .padding(.horizontal, metrics.margin)
            }
            HStack(spacing: K7Space.s8) {
                GlassSegments(items: SongTabs.ordered(live).map { ($0, $0.rawValue, !tabs.contains($0)) }, selection: current, wide: metrics.wide) { pick($0) }
                if metrics.wide {
                    Spacer(minLength: 0)
                    if hasStems { versionSwitch }
                    Button { selected = .info } label: {
                        Image(systemName: current == .info ? "info.circle.fill" : "info.circle").font(.system(size: 20)).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Info")
                    .accessibilityAddTraits(current == .info ? .isSelected : [])
                }
            }
            .padding(.horizontal, metrics.margin)
            // The piano has no capo: its chords already read in the sounding key. The tab stays a guitar's.
            if live.capo > 0, current == .tab || (current == .chords && model.prefs.instrument == .guitar) { capoNote }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, 6)
        .screenBackground()
        .k7Header(live.title, subtitle: live.artist)
        .toolbar { header }
        .popover(isPresented: $menuOpen, attachmentAnchor: .point(.topTrailing), arrowEdge: .top) {
            SongMenu(
                song: live,
                edit: { kind in menuOpen = false; editing = kind },
                importLRC: { menuOpen = false; picking = .lrc; pickedKind = .lrc },
                downloadLyrics: { menuOpen = false; Task { await model.downloadLyrics(for: live) } },
                stems: { menuOpen = false; stemsOpen = true },
                addSheet: { menuOpen = false; picking = .sheet; pickedKind = .sheet },
                info: metrics.wide ? nil : { menuOpen = false; selected = .info },
                instrumental: metrics.wide || !hasStems ? nil : model.playsInstrumental(live),
                switchVersion: { Task { await model.switchVersion(of: live) } })
                .presentationCompactAdaptation(.popover)
                .presentationBackground(k7.menu)
        }
        .task {
            if let t = DebugLaunch.tab { selected = t }
            if let at = DebugLaunch.seek, let url = model.playURL(of: live) { model.seek(id: playID, url: url, to: at); refreshActive() }
            menuOpen = DebugLaunch.menu
            hasStems = model.stems.existing(for: live) != nil
        }
        // Read again when iCloud delivers a file: a song added on another device may arrive while it is shown.
        .task(id: model.sync?.deliveries) { if wave.samples.isEmpty { wave = await model.library.wave(of: live) } }
        .task(id: "\(playing)-\(current.rawValue)") { await follow() }
        .onAppear { model.shownSong = live }
        .onDisappear { if model.shownSong?.id == live.id { model.shownSong = nil } }
        .onChange(of: current) { refreshActive() }
        .onChange(of: stemsOpen) { hasStems = model.stems.existing(for: live) != nil }
        .sheet(isPresented: $stemsOpen) { StemsSheet(song: live) }
        // The model is given again: sized by WindowFraction on the Mac, the sheet is measured outside this environment.
        .sheet(item: $editing) { kind in TextEditorSheet(song: live, kind: kind).environment(model) }
        .fileImporter(
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            allowedContentTypes: picking == .lrc ? [UTType(filenameExtension: "lrc") ?? .plainText, .plainText] : Self.sheetTypes
        ) { result in
            let kind = pickedKind
            guard case .success(let url) = result else { return }
            Task { if kind == .lrc { await importLRC(url) } else { await report(await model.library.addSheet(from: url, to: live)) } }
        }
    }

    /// Play and the song's menu, side by side at the right of the bar, so the glass makes them one capsule; play only with audio.
    @ToolbarContentBuilder private var header: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { Task { await model.toggleFavorite(live) } } label: {
                Image(systemName: live.favorite ? "star.fill" : "star").frame(minWidth: 30, minHeight: 30)
            }
            .accessibilityLabel(live.favorite ? "Remove from favourites" : "Add to favourites")
            // A song made without audio has nothing to play, so no play button.
            if live.audioURL != nil {
                Button {
                    if let url = model.playURL(of: live) { model.togglePlay(id: playID, url: url) }
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill").frame(minWidth: 30, minHeight: 30)
                }
                .accessibilityLabel(playing ? "Pause" : "Play")
                .disabled(model.playURL(of: live) == nil)
            }
            #if targetEnvironment(macCatalyst)
            // A popover anchored in the bar does not open under Catalyst; the Mac gets a menu of the same actions.
            Menu { actions() } label: { Image(systemName: "ellipsis").frame(minWidth: 30, minHeight: 30) }
                .accessibilityLabel("Song menu")
            #else
            Button { menuOpen = true } label: { Image(systemName: "ellipsis").frame(minWidth: 30, minHeight: 30) }
                .accessibilityLabel("Song menu")
            #endif
        }
    }

    /// A tab with content opens; an empty one asks for it, and opens once it is there.
    private func pick(_ t: SongTab) {
        selected = t
        guard !tabs.contains(t) else { return }
        switch t {
        case .chords: editing = .chords
        case .lyrics: editing = .lyrics
        case .tab: editing = .tabs
        case .sheets: picking = .sheet; pickedKind = .sheet
        case .info: break
        }
    }

    private func actions() -> SongActions {
        SongActions(
            song: live,
            edit: { editing = $0 },
            importLRC: { picking = .lrc; pickedKind = .lrc },
            downloadLyrics: { Task { await model.downloadLyrics(for: live) } },
            stems: { stemsOpen = true },
            addSheet: { picking = .sheet; pickedKind = .sheet })
    }

    /// "Capo 3" above the chords and the tab, which are written for the hand on the capo.
    private var capoNote: some View {
        Label("Capo \(live.capo)", systemImage: "guitars")
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(k7.accentIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.margin)
            .accessibilityIdentifier("capo")
    }

    /// Full song or instrumental, left of Info; it exists once the song has stems.
    private var versionSwitch: some View {
        let instrumental = model.playsInstrumental(live)
        return Button { Task { await model.switchVersion(of: live) } } label: {
            Group {
                if model.mixing { ProgressView() } else { Image(systemName: instrumental ? "mic.slash" : "mic").font(.system(size: 20)) }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(instrumental ? .accentColor : nil)
        .disabled(model.mixing)
        .accessibilityLabel(instrumental ? "Play the full song" : "Play the instrumental")
        .accessibilityIdentifier("versionSwitch")
    }

    @ViewBuilder private var content: some View {
        switch current {
        case .chords:
            let diagrams = live.hasDiagrams ? SongText.diagramChords(chords: live.chords, lyrics: live.lyrics, semitones: semitones) : []
            HStack(alignment: .top, spacing: 0) {
                ChordsTab(text: live.chords, semitones: semitones, active: active, onTap: seek, tappable: !metrics.wide && !diagrams.isEmpty)
                if metrics.wide, !diagrams.isEmpty { DiagramColumn(chords: diagrams).frame(width: 176).padding(.trailing, metrics.margin) }
            }
        case .lyrics: LyricsTab(text: live.lyrics, active: active, onTap: seek)
        case .tab: TabTab(text: live.tab)
        case .sheets: SheetsTab(song: live) { picking = .sheet; pickedKind = .sheet }
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

    /// What the sheet picker takes: PDFs, images and MusicXML scores, compressed or not.
    static let sheetTypes: [UTType] = [.pdf, .image, .xml] + SheetKind.scoreExtensions.compactMap { UTType(filenameExtension: $0) }
}

/// Which tabs a song has content for and which one it opens on; every one of `shown` is in the switch.
enum SongTabs {
    static let shown: [SongTab] = [.chords, .lyrics, .sheets, .tab]

    /// The switch's order: the tabs with content first, then the empty ones, each group in `shown`'s order.
    static func ordered(_ song: Song) -> [SongTab] {
        let full = available(song)
        return full + shown.filter { !full.contains($0) }
    }

    static func available(_ song: Song) -> [SongTab] {
        var out: [SongTab] = []
        if song.hasChords { out.append(.chords) }
        if song.hasLyrics { out.append(.lyrics) }
        if song.hasSheets { out.append(.sheets) }
        if song.hasTab { out.append(.tab) }
        return out
    }

    /// Chords, else lyrics, else sheets, else tab; Info only when the song has none.
    static func opening(_ song: Song) -> SongTab { available(song).first ?? .info }
}
