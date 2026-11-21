// The Songs list and the import button that hands picked URLs, or a file server's files, to the library seam.
import SwiftUI
import UniformTypeIdentifiers

struct SongsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var pickFolder = false
    @State private var path: [Song] = []
    @State private var browsingServer = false
    @State private var missingOpen = false
    @State private var missingArtist = ""
    @State private var missingTitle = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var metrics: Metrics { Metrics(sizeClass) }

    var body: some View {
        NavigationStack(path: $path) {
            // A ZStack, not an overlay: an overlay of the scroll view proposed no width, and the empty state wrapped at every word.
            ZStack {
                ScrollView {
                    CardRows(items: model.library.songs, separatorInset: 74) { song in
                        NavigationLink(value: song) {
                            RowLabel(title: song.title, second: song.artist) { IconTile(symbol: "music.note") }
                                .padding(.leading, K7Space.s20).padding(.trailing, K7Space.s16)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, metrics.margin).padding(.top, 8)
                    .opacity(model.library.songs.isEmpty ? 0 : 1)
                }
                if model.library.songs.isEmpty {
                    EmptyState(symbol: "music.note", title: "No songs yet", sentence: "Import a song folder or an audio file with Add song.")
                }
            }
            .screenBackground()
            .k7Header("Songs", subtitle: count(model.library.songs.count, "song"))
            .onChange(of: model.library.songs.count) { if DebugLaunch.openFirst, path.isEmpty, let s = model.library.songs.first { path = [s] } }
            .navigationDestination(for: Song.self) { SongScreen(song: $0) }
            .onChange(of: model.sharedSong, initial: true) { _, id in
                guard let id, let song = model.library.songs.first(where: { $0.id == id }) else { return }
                path = [song]
                model.sharedSong = nil
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Import a folder", systemImage: "folder") { pickFolder = true; picking = true }
                        Button("Import audio files", systemImage: "waveform") { pickFolder = false; picking = true }
                        if model.server.connected {
                            Button("From the file server", systemImage: "externaldrive.connected.to.line.below") { browsingServer = true }
                            Button("Missing song", systemImage: "questionmark.circle") { missingOpen = true }
                        }
                    } label: {
                        if metrics.wide { Label("Add song", systemImage: "plus").labelStyle(.titleAndIcon) } else { Image(systemName: "plus") }
                    }
                    .accessibilityLabel("Add song")
                }
            }
            .sheet(isPresented: $browsingServer) { ServerImportSheet() }
            .alert("Missing song", isPresented: $missingOpen) {
                TextField("Artist", text: $missingArtist)
                TextField("Title", text: $missingTitle)
                Button("Cancel", role: .cancel) { (missingArtist, missingTitle) = ("", "") }
                Button("Add") {
                    let (artist, title) = (missingArtist, missingTitle)
                    (missingArtist, missingTitle) = ("", "")
                    Task { await model.reportMissingSong(artist: artist, title: title) }
                }
            } message: { Text("It is written to MISSING-SONGS.md at the root of your file server.") }
            .fileImporter(
                isPresented: $picking,
                allowedContentTypes: pickFolder ? [.folder] : [.audio],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { Task { await model.importURLs(urls) } }
            }
        }
    }
}

/// "1 song", "3 songs": a count and its noun for a screen's subtitle.
func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
