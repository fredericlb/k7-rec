// Browses the user's file server and imports the audio files ticked there, as if they were picked in Files.
// What a reader gets wrong: files are downloaded first, then imported together; nothing is kept on the server side.
import SwiftUI

struct ServerImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var entries: [RemoteEntry] = []
    @State private var picked: Set<String> = []
    @State private var loading = true
    @State private var failure: String?
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                if path != "/" {
                    Button { open(parent) } label: { Label("Up", systemImage: "arrow.turn.left.up") }
                }
                ForEach(entries.filter { $0.isFolder || $0.isAudio }) { entry in
                    if entry.isFolder {
                        Button { open(join(entry.name)) } label: { Label(entry.name, systemImage: "folder") }
                    } else {
                        Button { toggle(entry) } label: {
                            HStack {
                                Label(entry.name, systemImage: "waveform")
                                Spacer()
                                if picked.contains(join(entry.name)) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                            }
                        }
                        .accessibilityAddTraits(picked.contains(join(entry.name)) ? .isSelected : [])
                    }
                }
            }
            .overlay {
                if loading { ProgressView() } else if let failure { ContentUnavailableView("Could not open the folder", systemImage: "exclamationmark.triangle", description: Text(failure)) }
                else if entries.allSatisfy({ !$0.isFolder && !$0.isAudio }) { ContentUnavailableView("No audio here", systemImage: "waveform") }
            }
            .navigationTitle(path.isEmpty ? "Server" : (path as NSString).lastPathComponent.isEmpty ? "/" : (path as NSString).lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(importing) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(importing ? model.server.progress : "Import \(picked.count)") { Task { await run() } }
                        .disabled(picked.isEmpty || importing)
                }
            }
            .task { open(model.server.folder) }
        }
        .interactiveDismissDisabled(importing)
    }

    private var parent: String {
        let up = (path as NSString).deletingLastPathComponent
        return up.isEmpty ? "/" : up
    }

    private func join(_ name: String) -> String { path == "/" ? "/" + name : path + "/" + name }

    private func toggle(_ entry: RemoteEntry) {
        let full = join(entry.name)
        if picked.contains(full) { picked.remove(full) } else { picked.insert(full) }
    }

    private func open(_ next: String) {
        path = next.isEmpty ? "/" : next
        loading = true
        failure = nil
        Task {
            do { entries = try await model.server.list(path) } catch { entries = []; failure = error.localizedDescription }
            loading = false
        }
    }

    private func run() async {
        importing = true
        let ok = await model.importFromServer(picked.sorted())
        importing = false
        if ok { dismiss() }
    }
}
