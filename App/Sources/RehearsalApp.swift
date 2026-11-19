// App entry: one library, one recorder and one player, shared by every screen.
import SwiftUI

@main
struct RehearsalApp: App {
    @State private var model = AppModel.live()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
                .onChange(of: phase) { _, now in if now == .active { model.sync?.schedule() } }
                .task { await model.recoverTakes() }
                .task { await importFromLaunchArguments() }
        }
        .commands {
            CommandMenu("Recording") {
                Button(model.recording ? "Show Take" : "Record") {
                    if model.recording { model.recorderOpen = true } else { Task { await model.startTake(song: model.shownSong) } }
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Metronome") { model.recorderOpen = true }
            }
        }
    }

    // Debug builds import the paths of `-ImportOnLaunch a:b` so the simulator needs no picker (docs/app.md).
    private func importFromLaunchArguments() async {
        #if DEBUG
        if let seed = UserDefaults.standard.string(forKey: "SeedTake"), let rec = model.recorder as? StoreTakeRecorder {
            await rec.seed(from: URL(fileURLWithPath: seed))
        }
        guard let list = UserDefaults.standard.string(forKey: "ImportOnLaunch") else { return }
        await model.importURLs(list.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
        #endif
    }
}
