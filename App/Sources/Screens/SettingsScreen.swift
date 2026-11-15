// Settings: a placeholder form until the packages bring real options.
import SwiftUI

struct SettingsScreen: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Recording") { Text("Microphone and normalizing come with the audio package.") }
                Section("About") { LabeledContent("Version", value: "0.1.0") }
            }
            .navigationTitle("Settings")
        }
    }
}
