// The info tab: title and artist as read, the transposition, tags editable, the date the song was added.
import SwiftUI

struct InfoTab: View {
    @Environment(AppModel.self) private var model
    let song: Song
    @State private var tags = ""
    @State private var loaded = false

    var body: some View {
        Form {
            LabeledContent("Title", value: song.title)
            LabeledContent("Artist", value: song.artist.isEmpty ? "-" : song.artist)
            LabeledContent("Added", value: song.added.formatted(date: .abbreviated, time: .omitted))
            Section("Transpose") {
                let semitones = model.prefs.transpose(of: song.id)
                HStack {
                    Label("Transpose", systemImage: "plusminus")
                    Spacer()
                    StepperControl(
                        label: semitones > 0 ? "+\(semitones)" : "\(semitones)", minusLabel: "Transpose down", plusLabel: "Transpose up",
                        minus: { model.prefs.setTranspose(semitones - 1, of: song.id) }, plus: { model.prefs.setTranspose(semitones + 1, of: song.id) })
                    Button("Reset") { model.prefs.setTranspose(0, of: song.id) }.disabled(semitones == 0)
                }
            }
            Section("Tags (comma separated)") {
                TextField("rock, 120 bpm", text: $tags)
                    .textInputAutocapitalization(.never)
                    .onSubmit(commit)
            }
        }
        .onAppear { if !loaded { tags = song.tags.joined(separator: ", "); loaded = true } }
        .onDisappear(perform: commit)
    }

    private func commit() {
        let list = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard list != song.tags else { return }
        Task { if let failure = await model.library.setTags(list, for: song) { model.notice = failure } }
    }
}
