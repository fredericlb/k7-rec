// Four tabs; the Recording tab turns red while a take runs.
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            SongsScreen().tabItem { Label("Songs", systemImage: "music.note.list") }
            TakesScreen().tabItem { Label("Takes", systemImage: "waveform") }
            RecordingScreen().tabItem { recordingItem }
            SettingsScreen().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .alert("Rehearsal", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") {}
        } message: { Text(model.notice ?? "") }
    }

    @ViewBuilder private var recordingItem: some View {
        if model.recording {
            Label { Text("Recording") } icon: { Image(systemName: "record.circle.fill").renderingMode(.original).foregroundStyle(.red) }
        } else {
            Label("Recording", systemImage: "record.circle")
        }
    }
}
