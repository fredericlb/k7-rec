// The Songs list and the import button that hands picked URLs to the library seam.
import SwiftUI
import UniformTypeIdentifiers

struct SongsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var pickFolder = false

    var body: some View {
        NavigationStack {
            List(model.library.songs) { song in
                NavigationLink(value: song) {
                    VStack(alignment: .leading) {
                        Text(song.title).font(.headline)
                        if !song.artist.isEmpty { Text(song.artist).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Songs")
            .navigationDestination(for: Song.self) { SongScreen(song: $0) }
            .toolbar {
                Menu {
                    Button("Import a folder", systemImage: "folder") { pickFolder = true; picking = true }
                    Button("Import audio files", systemImage: "waveform") { pickFolder = false; picking = true }
                } label: { Image(systemName: "plus") }
            }
            .fileImporter(
                isPresented: $picking,
                allowedContentTypes: pickFolder ? [.folder] : [.audio],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { model.library.importURLs(urls) }
            }
        }
    }
}
