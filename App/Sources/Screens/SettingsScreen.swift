// Settings: the lyrics lead, the headset microphone and the About line.
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $prefs.lyricsLead, in: 0...5, step: 0.5) { LabeledContent("Lyrics lead", value: String(format: "%.1f s", prefs.lyricsLead)) }
                } header: { Text("Playing") } footer: { Text("A tap on a timed lyric line starts the song this much before it.") }
                Section {
                    Toggle("Use the headset microphone", isOn: $prefs.headsetInput)
                } header: { Text("Recording") } footer: { Text("Off: takes use the phone's microphone and earphones keep full-quality sound. On: a Bluetooth headset's own microphone, in narrowband sound.") }
                Section("About") { LabeledContent("Version", value: "0.1.0") }
            }
            .navigationTitle("Settings")
        }
    }
}
