// Three tabs; the recorder bar sits above them while a take runs.
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            SongsScreen().tabItem { Label("Songs", systemImage: "music.note.list") }
            TakesScreen().tabItem { Label("Takes", systemImage: "waveform") }
            SettingsScreen().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.recording { RecorderBar().transition(.move(edge: .bottom)) }
        }
        .animation(.default, value: model.recording)
        .alert("Rehearsal", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") {}
        } message: { Text(model.notice ?? "") }
    }
}
