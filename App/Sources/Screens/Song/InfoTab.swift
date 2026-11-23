// The info tab, as the design system's cards: title and artist editable, the date added, the transposition (the
// sheets and the sound move together), the capo, the tags as chips with a field to add one. Every edit is saved as made.
import SwiftUI

struct InfoTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let song: Song
    @State private var title = ""
    @State private var artist = ""
    @State private var newTag = ""
    @State private var loaded = false

    var body: some View {
        let metrics = Metrics(sizeClass)
        ScrollView {
            VStack(spacing: K7Space.s24) {
                about
                transpose
                capo
                tags
            }
            .frame(maxWidth: metrics.wide ? 640 : .infinity)
            .padding(.horizontal, metrics.margin).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if !loaded { (title, artist, loaded) = (song.title, song.artist, true) } }
        .onDisappear { save() }
    }

    private var about: some View {
        SettingsCard("Song") {
            FieldRow(label: "Title", text: $title, placeholder: "Title", capitalized: true).onSubmit { save() }
            Separator()
            FieldRow(label: "Artist", text: $artist, placeholder: "Artist", capitalized: true).onSubmit { save() }
            Separator()
            SettingRow("Added") { Value(song.added.formatted(date: .abbreviated, time: .omitted)) }
        }
    }

    private var transpose: some View {
        let semitones = model.prefs.transpose(of: song.id)
        return SettingsCard("Transpose", note: "Chords, diagrams and the song's sound move together; the tempo stays the same.") {
            SettingRow("Semitones") {
                StepperControl(
                    label: semitones > 0 ? "+\(semitones)" : "\(semitones)", minusLabel: "Transpose down", plusLabel: "Transpose up",
                    valueInside: false,
                    minus: { model.setTranspose(semitones - 1, of: song.id) }, plus: { model.setTranspose(semitones + 1, of: song.id) })
            }
            Separator()
            ActionRow(title: "Reset", busy: false, enabled: semitones != 0) { model.setTranspose(0, of: song.id) }
        }
    }

    private var capo: some View {
        let fret = song.capo
        return SettingsCard("Capo", note: "The fret the capo sits on; Chords and Tab show it.") {
            SettingRow("Fret") {
                StepperControl(
                    label: fret == 0 ? "None" : "\(fret)", minusLabel: "Capo down", plusLabel: "Capo up", valueInside: false,
                    minus: { if fret > 0 { Task { await model.setCapo(fret - 1, of: song) } } },
                    plus: { if fret < 12 { Task { await model.setCapo(fret + 1, of: song) } } })
            }
        }
    }

    private var tags: some View {
        SettingsCard("Tags", note: "Words to find the song by: a style, a tuning, a set list.") {
            if !song.tags.isEmpty {
                FlowRows(spacing: K7Space.s8) {
                    ForEach(song.tags, id: \.self) { tag in TagChip(text: tag) { save(tags: song.tags.filter { $0 != tag }) } }
                }
                .padding(.horizontal, K7Space.s16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                Separator()
            }
            HStack(spacing: K7Space.s12) {
                TextField("Add a tag", text: $newTag, prompt: Text("Add a tag").foregroundStyle(k7.textPlaceholder))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addTag)
                    .frame(minHeight: K7Size.touch)
                Button(action: addTag) { Image(systemName: "plus.circle.fill").font(.system(size: 22)) }
                    .buttonStyle(.plain).foregroundStyle(newTag.isBlank ? k7.textPlaceholder : k7.accentSoft)
                    .disabled(newTag.isBlank)
                    .accessibilityLabel("Add tag")
            }
            .frame(minHeight: K7Size.row)
            .padding(.leading, K7Space.s20).padding(.trailing, K7Space.s16)
        }
    }

    private func addTag() {
        let added = newTag.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !song.tags.contains($0) }
        newTag = ""
        if !added.isEmpty { save(tags: song.tags + added) }
    }

    /// Writes what changed; an emptied title keeps the one before.
    private func save(tags: [String]? = nil) {
        let t = title.trimmingCharacters(in: .whitespaces), a = artist.trimmingCharacters(in: .whitespaces)
        let newTitle = t.isEmpty ? song.title : t, newTags = tags ?? song.tags
        if t.isEmpty { title = song.title }
        guard newTitle != song.title || a != song.artist || newTags != song.tags else { return }
        let current = song
        Task { if let failure = await model.library.setInfo(title: newTitle, artist: a, tags: newTags, for: current) { model.notice = failure } }
    }
}

/// One tag: its word and a button that removes it.
private struct TagChip: View {
    let text: String
    let remove: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 15, weight: .semibold))
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(k7.textSecondary)
                .accessibilityLabel("Remove \(text)")
        }
        .padding(.leading, 14).padding(.trailing, 4).frame(minHeight: 36)
        .fillControl()
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespaces).isEmpty }
}
