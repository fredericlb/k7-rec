// Three tabs on iPhone, a sidebar on iPad (iOS 18 adaptive style); the recorder bar sits above the tabs.
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
    }
}
