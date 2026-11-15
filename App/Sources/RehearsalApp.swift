// App entry: one library, one recorder and one player, shared by every screen.
// Fakes stand in until the packages are wired (docs/app.md).
import SwiftUI

@main
struct RehearsalApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
        }
    }
}
