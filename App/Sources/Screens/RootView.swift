// Three tabs; the take panel opens over them from the rec button (RecButton.swift).
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            SongsScreen().tabItem { Label("Songs", systemImage: "music.note.list") }
            TakesScreen().tabItem { Label("Takes", systemImage: "waveform") }
            SettingsScreen().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: Bindable(model).recorderOpen) { RecordingScreen() }
        .alert("Rehearsal", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") {}
        } message: { Text(model.notice ?? "") }
    }
}
