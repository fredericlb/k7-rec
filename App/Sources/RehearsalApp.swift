// App entry: one library, one recorder and one player, shared by every screen.
import SwiftUI

@main
struct RehearsalApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
                .task { await model.recoverTakes() }
                .task { await importFromLaunchArguments() }
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
