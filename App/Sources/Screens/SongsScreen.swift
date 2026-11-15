// The Songs list and the import button that hands picked URLs to the library seam.
import SwiftUI
import UniformTypeIdentifiers

struct SongsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var pickFolder = false
    @State private var path: [Song] = []
    @State private var pickingMusic: MusicPick?

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
            .toolbar {
                Menu {
                    Button("Import a folder", systemImage: "folder") { pickFolder = true; picking = true }
                    Button("Import audio files", systemImage: "waveform") { pickFolder = false; picking = true }
                    Button("From Apple Music", systemImage: "music.note") { openPicker(cloud: false) }
                    Button("From Apple Music, streamed too", systemImage: "icloud") { openPicker(cloud: true) }
                } label: { Image(systemName: "plus") }
            }
            .sheet(item: $pickingMusic) { pick in
                MediaPicker(cloud: pick == .streamed) { items in
                    pickingMusic = nil
                    Task { await model.importAppleMusic(items) }
                } onCancel: { pickingMusic = nil }
            }
            .overlay(alignment: .bottom) { if let p = model.appleMusic.progress { ImportProgress(progress: p) } }
            .fileImporter(
                isPresented: $picking,
                allowedContentTypes: pickFolder ? [.folder] : [.audio],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { Task { await model.importURLs(urls) } }
            }
        }
    }

    private func openPicker(cloud: Bool) {
        Task { if await model.allowAppleMusic() { pickingMusic = cloud ? .streamed : .owned } }
    }
}

/// Which tracks the media picker lists: the ones owned, or the streamed ones too.
enum MusicPick: Identifiable { case owned, streamed; var id: Self { self } }
