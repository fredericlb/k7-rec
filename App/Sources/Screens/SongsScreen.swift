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

    var body: some View {
        NavigationStack(path: $path) {
            List(model.library.songs) { song in
                NavigationLink(value: song) {
                    VStack(alignment: .leading) {
                        Text(song.title).font(.headline)
                        if !song.artist.isEmpty { Text(song.artist).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
            .overlay {
                if model.library.songs.isEmpty {
                    ContentUnavailableView("No songs yet", systemImage: "music.note.list", description: Text("Import a song folder or an audio file with +."))
                }
            }
            .onChange(of: model.library.songs.count) { if DebugLaunch.openFirst, path.isEmpty, let s = model.library.songs.first { path = [s] } }
            .navigationTitle("Songs")
            .navigationDestination(for: Song.self) { SongScreen(song: $0) }
            .recButton()
            .toolbar {
                Menu {
                    Button("Import a folder", systemImage: "folder") { pickFolder = true; picking = true }
                    Button("Import audio files", systemImage: "waveform") { pickFolder = false; picking = true }
                    if model.server.connected {
                        Button("From the file server", systemImage: "externaldrive.connected.to.line.below") { browsingServer = true }
                        Button("Missing song", systemImage: "questionmark.circle") { missingOpen = true }
                    }
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Import")
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
