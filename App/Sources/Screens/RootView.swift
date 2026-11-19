// Three tabs and the app header's rec button, which opens the take panel over them: a view on the
// iPhone and iPad (RecButton.swift), a title bar item on the Mac (MacRecToolbarItem.swift).
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    #if targetEnvironment(macCatalyst)
    @State private var macRec: MacRecToolbarItem?
    #endif

    var body: some View {
        TabView {
            SongsScreen().tabItem { Label("Songs", systemImage: "music.note.list") }
            TakesScreen().tabItem { Label("Takes", systemImage: "waveform") }
            SettingsScreen().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        #if targetEnvironment(macCatalyst)
        .onAppear { if macRec == nil { macRec = MacRecToolbarItem(model: model); macRec?.start() } }
        #else
        .overlay(alignment: .topTrailing) { RecButton().padding(.trailing, 12) }
        #endif
        .sheet(isPresented: Bindable(model).recorderOpen) { RecordingScreen() }
        .alert("Rehearsal", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") {}
        } message: { Text(model.notice ?? "") }
    }
}
